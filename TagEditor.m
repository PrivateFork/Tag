/*
 *  $Id$
 *
 *  Copyright (C) 2005, 2006 Stephen F. Booth <me@sbooth.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import "TagEditor.h"
#import "KeyValueTaggedFile.h"
#import "Genres.h"
#import "AddTagSheet.h"
#import "GuessTagsSheet.h"

#import "UKKQueue.h"

static TagEditor *sharedEditor = nil;

@interface TagEditor (Private)
- (BOOL)	addOneFile:(NSString *)filename atIndex:(unsigned)index;
- (void)	alertDidEnd:(NSAlert *)alert returnCode:(int)returnCode  contextInfo:(void  *)contextInfo;
- (void)	tagsChanged;
- (void)	undoManagerNotification:(NSNotification *)aNotification;
@end

@implementation TagEditor

+ (void) initialize
{
	NSColor		*defaultColor;
	NSArray		*defaultValues;
	NSArray		*defaultKeys;

	defaultColor	= [NSColor colorWithCalibratedRed:1.0 green:(250.0/255.0) blue:(178.0/255.0) alpha:1.0];
	defaultValues	= [NSArray arrayWithObjects:[NSArchiver archivedDataWithRootObject:defaultColor], NSLocalizedStringFromTable(@"<Multiple Values>", @"General", @""), nil];
	defaultKeys		= [NSArray arrayWithObjects:@"multipleValuesMarkerColor", @"multipleValuesDescription", nil];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjects:defaultValues forKeys:defaultKeys]];
}

+ (TagEditor *) sharedEditor
{
	@synchronized(self) {
		if(nil == sharedEditor) {
			sharedEditor = [[self alloc] init];
		}
	}
	return sharedEditor;
}

+ (id) allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if(nil == sharedEditor) {
            return [super allocWithZone:zone];
        }
    }
    return sharedEditor;
}

- (id) init
{
	if((self = [super initWithWindowNibName:@"TagEditor"])) {

		_validKeys	= [[NSArray arrayWithObjects:@"title", @"artist", @"album", @"year", @"genre", @"composer", @"MCN", @"ISRC", @"encoder", @"comment", @"trackNumber", @"trackTotal", @"discNumber", @"discTotal", @"compilation", @"custom", nil] retain];
		_files		= [[NSMutableArray arrayWithCapacity:20] retain];
		
		[[UKKQueue sharedFileWatcher] setDelegate:self];

		return self;
	}
	return nil;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:[self undoManager]];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:[self undoManager]];

	[_validKeys release];
	[_files release];
	
	[super dealloc];
}

- (id)				copyWithZone:(NSZone *)zone					{ return self; }
- (id)				retain										{ return self; }
- (unsigned)		retainCount									{ return UINT_MAX;  /* denotes an object that cannot be released */ }
- (void)			release										{ /* do nothing */ }
- (id)				autorelease									{ return self; }

- (NSArray *)		genres										{ return [Genres sharedGenres]; }
- (NSWindow *)		windowForSheet								{ return [self window]; }
- (IBAction)		toggleFilesDrawer:(id)sender				{ [_filesDrawer toggle:sender]; }
- (IBAction)		openFilesDrawer:(id)sender					{ [_filesDrawer open:sender]; }
- (IBAction)		closeFilesDrawer:(id)sender					{ [_filesDrawer close:sender]; }
- (unsigned)		openFileCount								{ return [[_filesController arrangedObjects] count]; }
- (unsigned)		selectedFileCount							{ return [[_filesController selectedObjects] count]; }
- (IBAction)		selectNextFile:(id)sender					{ [_filesController selectNext:sender]; }
- (IBAction)		selectPreviousFile:(id)sender				{ [_filesController selectPrevious:sender]; }
- (IBAction)		selectAllFiles:(id)sender					{ [_filesController setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self openFileCount])]]; }

- (IBAction)		selectBasicTab:(id)sender					{ [_tabView selectTabViewItemAtIndex:kBasicTabViewItemIndex]; }
- (IBAction)		selectAdvancedTab:(id)sender				{ [_tabView selectTabViewItemAtIndex:kAdvancedTabViewItemIndex]; }
- (IBAction)		selectTabularTab:(id)sender					{ [_tabView selectTabViewItemAtIndex:kTabularTabViewItemIndex]; }

- (NSUndoManager *) undoManager									{ return [[self window] undoManager]; }

- (void) undoManagerNotification:(NSNotification *)aNotification
{
	NSString	*name	= [aNotification name];
	
	if([name isEqualToString:NSUndoManagerDidUndoChangeNotification]) {
		[self tagsChanged];
	}
	else if([name isEqualToString:NSUndoManagerDidRedoChangeNotification]) {
		[self tagsChanged];
	}
}

- (BOOL) applicationShouldTerminate
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSAlert					*alert;
	int						result;

	if(0 == [self openFileCount] || NO == [self dirty]) {
		return YES;
	}
	else {
		enumerator = [[_filesController arrangedObjects] objectEnumerator];
		while((current = [enumerator nextObject])) {
			if(YES == [current dirty]) {
				alert = [[[NSAlert alloc] init] autorelease];
				[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
				[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Cancel", @"General", @"")];
				[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Don't Save", @"General", @"")];
				[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Do you want to save the changes you made in the document \"%@\"?", @"General", @""), [current displayName]]];
				[alert setInformativeText:NSLocalizedStringFromTable(@"Your changes will be lost if you don't save them.", @"General", @"")];
				[alert setAlertStyle:NSInformationalAlertStyle];
				
				result = [alert runModal];
				switch(result) {
					case NSAlertFirstButtonReturn:		[current save];				break;
					case NSAlertSecondButtonReturn:		return NO;					break;
					case NSAlertThirdButtonReturn:		;							break;
				}
			}
		}
		
		return YES;
	}
}

- (void) awakeFromNib
{
	[_tagsTable setAutosaveTableColumns:YES];
	[_tabularTagsTable setAutosaveTableColumns:YES];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(undoManagerNotification:) name:NSUndoManagerDidUndoChangeNotification object:[self undoManager]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(undoManagerNotification:) name:NSUndoManagerDidRedoChangeNotification object:[self undoManager]];

	[_tagsController setSortDescriptors:[NSArray arrayWithObjects:
		[[[NSSortDescriptor alloc] initWithKey:@"key" ascending:YES] autorelease],
		[[[NSSortDescriptor alloc] initWithKey:@"value" ascending:YES] autorelease],
		nil]];
	[_selectedFilesController setSortDescriptors:[NSArray arrayWithObjects:
		[[[NSSortDescriptor alloc] initWithKey:@"artist" ascending:YES] autorelease],
		[[[NSSortDescriptor alloc] initWithKey:@"album" ascending:YES] autorelease],
		[[[NSSortDescriptor alloc] initWithKey:@"trackNumber" ascending:YES] autorelease],
		nil]];
}

- (void) windowDidLoad
{
	[self setShouldCascadeWindows:NO];
	[self setWindowFrameAutosaveName:@"Editor"];
	[[self window] setExcludedFromWindowsMenu:YES];
}

- (BOOL) dirty
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;

	enumerator	= [[_filesController arrangedObjects] objectEnumerator];	
	while((current = [enumerator nextObject])) {
		if([current dirty]) {
			return YES;
		}
	}
	
	return NO;
}

- (BOOL) selectionDirty
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	
	enumerator	= [[_filesController selectedObjects] objectEnumerator];	
	while((current = [enumerator nextObject])) {
		if([current dirty]) {
			return YES;
		}
	}
	
	return NO;
}

#pragma mark File Manipulation

- (IBAction) openDocument:(id)sender
{
	BOOL				success				= YES;
	NSOpenPanel			*panel				= [NSOpenPanel openPanel];
	NSArray				*allowedTypes		= [NSArray arrayWithObjects:@"flac", @"ogg", @"ape", @"apl", @"mac", nil];
	NSEnumerator		*enumerator;
	NSString			*filename;
	NSMutableArray		*newFiles;
	KeyValueTaggedFile	*file;
	int					returnCode;
	
	[panel setAllowsMultipleSelection:YES];
	[panel setCanChooseDirectories:YES];
	
	returnCode = [panel runModalForTypes:allowedTypes];
	
	if(NSOKButton == returnCode) {		

		newFiles	= [NSMutableArray arrayWithCapacity:10];
		enumerator	= [[panel filenames] objectEnumerator];
		
		while((filename = [enumerator nextObject])) {
			success &= [self addFile:filename];

			if(success) {
				file = [_filesController findFile:filename];
				if(nil != file) {
					[newFiles addObject:file];
				}
			}
		}

		if(1 < [[panel filenames] count] && success) {
			[_filesController setSelectedObjects:newFiles];
		}
		
		if(1 < [self openFileCount]) {
			[self openFilesDrawer:self];
		}
	}
}

- (IBAction) performClose:(id)sender
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSString				*key;
	
	[self willChangeValueForKey:@"tags"];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		if(YES == [current dirty]) {
			NSAlert		*alert;
			int			result;
			
			alert = [[[NSAlert alloc] init] autorelease];
			[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
			[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Cancel", @"General", @"")];
			[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Don't Save", @"General", @"")];
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Do you want to save the changes you made in the document \"%@\"?", @"General", @""), [current displayName]]];
			[alert setInformativeText:NSLocalizedStringFromTable(@"Your changes will be lost if you don't save them.", @"General", @"")];
			[alert setAlertStyle:NSInformationalAlertStyle];
			
			result = [alert runModal];
			switch(result) {
				case NSAlertFirstButtonReturn:		[current save];				break;
				case NSAlertSecondButtonReturn:		continue;					break;
				case NSAlertThirdButtonReturn:		;							break;
			}
		}
		
		[_filesController removeObject:current];
		
		[[UKKQueue sharedFileWatcher] removePath:[current filename]];
	}
	[self didChangeValueForKey:@"tags"];
	
	enumerator = [_validKeys objectEnumerator];
	while((key = [enumerator nextObject])) {
		[self willChangeValueForKey:key];
		[self didChangeValueForKey:key];
	}

	if(1 >= [self openFileCount]) {
		[self closeFilesDrawer:self];
	}
}

- (IBAction) saveDocument:(id)sender
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		if([current dirty]) {
			@try {
				[current save];
			}
			@catch(NSException *exception) {
				NSAlert		*alert;
				
				alert = [[[NSAlert alloc] init] autorelease];
				[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
				[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"An error occurred while saving the document \"%@\".", @"Errors", @""), [current displayName]]];
				[alert setInformativeText:[exception reason]];
				[alert setAlertStyle:NSInformationalAlertStyle];
				[alert runModal];
			}
		}
	}
}

- (IBAction) revertDocumentToSaved:(id)sender
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSString				*key;
	
	[self willChangeValueForKey:@"tags"];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		if(YES == [current dirty]) {
			NSAlert		*alert;
			int			result;
			
			alert = [[[NSAlert alloc] init] autorelease];
			[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Revert", @"General", @"")];
			[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Cancel", @"General", @"")];
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Do you want to revert to the most recently saved revision of the document \"%@\"?", @"General", @""), [current displayName]]];
			[alert setInformativeText:NSLocalizedStringFromTable(@"Your changes will be lost if you don't save them.", @"General", @"")];
			[alert setAlertStyle:NSInformationalAlertStyle];
			
			result = [alert runModal];
			switch(result) {
				case NSAlertFirstButtonReturn:
					@try {
						[current revert];
					}
					@catch(NSException *exception) {
						alert = [[[NSAlert alloc] init] autorelease];
						[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
						[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"An error occurred while reverting the document \"%@\".", @"Errors", @""), [current displayName]]];
						[alert setInformativeText:[exception reason]];
						[alert setAlertStyle:NSInformationalAlertStyle];
						[alert runModal];
					}
					break;
					
				case NSAlertSecondButtonReturn:		continue;					break;
			}
		}
	}
	[self didChangeValueForKey:@"tags"];
	
	enumerator = [_validKeys objectEnumerator];
	while((key = [enumerator nextObject])) {
		[self willChangeValueForKey:key];
		[self didChangeValueForKey:key];
	}
}

- (BOOL) addFile:(NSString *)filename
{
	return [self addFile:filename atIndex:[[_filesController arrangedObjects] count]];
}

- (BOOL) addFile:(NSString *)filename atIndex:(unsigned)index
{
	NSFileManager		*manager			= [NSFileManager defaultManager];
	NSArray				*allowedTypes		= [NSArray arrayWithObjects:@"flac", @"ogg", @"ape", @"apl", @"mac", nil];
	NSMutableArray		*newFiles;
	KeyValueTaggedFile	*file;
	NSArray				*subpaths;
	BOOL				isDir;
	NSEnumerator		*enumerator;
	NSString			*subpath;
	NSString			*composedPath;
	BOOL				success				= YES;

	if([manager fileExistsAtPath:filename isDirectory:&isDir]) {
		newFiles = [NSMutableArray arrayWithCapacity:10];

		if(isDir) {
			subpaths	= [manager subpathsAtPath:filename];
			enumerator	= [subpaths objectEnumerator];
			
			while((subpath = [enumerator nextObject])) {
				composedPath = [NSString stringWithFormat:@"%@/%@", filename, subpath];
				
				// Ignore dotfiles
				if([[subpath lastPathComponent] hasPrefix:@"."]) {
					continue;
				}
				// Ignore files that don't have our extensions
				else if(NO == [allowedTypes containsObject:[subpath pathExtension]]) {
					continue;
				}
				
				// Ignore directories
				if([manager fileExistsAtPath:composedPath isDirectory:&isDir] && NO == isDir) {
					success &= [self addOneFile:composedPath atIndex:(unsigned)index];
				}

				if(success) {
					file = [_filesController findFile:composedPath];
					if(nil != file) {
						[newFiles addObject:file];
					}
				}
			}
			
			if(success) {
				[_filesController setSelectedObjects:newFiles];
			}
		}
		else {
			success &= [self addOneFile:filename atIndex:(unsigned)index];
			if(success) {
				[_filesController selectFile:filename];
			}
		}
	}
	else {
		NSAlert		*alert;
		
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"An error occurred while opening the document \"%@\".", @"Errors", @""), [filename lastPathComponent]]];
		[alert setInformativeText:NSLocalizedStringFromTable(@"The file was not found.", @"Errors", @"")];
		[alert setAlertStyle:NSInformationalAlertStyle];
		
		[alert runModal];
		success = NO;
	}
	
	return success;
}

- (BOOL) addOneFile:(NSString *)filename atIndex:(unsigned)index
{
	BOOL			success			= YES;

	@try {
		if([_filesController containsFile:filename]) {
			return YES;
		}
		
		[_filesController insertObject:[KeyValueTaggedFile parseFile:filename] atArrangedObjectIndex:index];
		[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filename]];

		[[UKKQueue sharedFileWatcher] addPath:filename];
	}
	
	@catch(NSException *exception) {
		NSAlert		*alert;
		
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"An error occurred while opening the document \"%@\".", @"Errors", @""), [filename lastPathComponent]]];
		[alert setInformativeText:[exception reason]];
		[alert setAlertStyle:NSInformationalAlertStyle];
		
		[alert runModal];
		success = NO;
	}

	return success;
}

#pragma mark Tag Manipulation

- (void) tagsChanged
{
	[self willChangeValueForKey:@"tags"];
	[self didChangeValueForKey:@"tags"];
}

- (IBAction) newTag:(id)sender
{
	AddTagSheet *sheet;
	
	@try {
		sheet = [[AddTagSheet alloc] init];
		[sheet setDelegate:self];
		[sheet showSheet];
		
		// TODO: How do I avoid a memory leak here?  For some reason sheet is being autoreleased while it is being displayed
		//[sheet autorelease];
	}

	@catch(NSException *exception) {
		NSAlert		*alert;
		
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText:NSLocalizedStringFromTable(@"Your Tag installation appears to be incomplete.", @"Errors", @"")];
		[alert setInformativeText:[exception reason]];
		[alert setAlertStyle:NSInformationalAlertStyle];
		
		[alert runModal];
	}
}

- (IBAction) deleteTag:(id)sender
{
	NSEnumerator			*enumerator, *tagEnumerator;
	KeyValueTaggedFile		*current;
	NSDictionary			*tag;
	NSUndoManager			*undoManager					= [self undoManager];
	
	[self willChangeValueForKey:@"tags"];
	[undoManager beginUndoGrouping];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		tagEnumerator = [[_tagsController selectedObjects] objectEnumerator];
		while((tag = [tagEnumerator nextObject])) {
			[current updateTag:[tag valueForKey:@"key"] withValue:[tag valueForKey:@"value"] toValue:nil];
		}
	}	
	[undoManager endUndoGrouping];
	[self didChangeValueForKey:@"tags"];
}

- (IBAction) guessTags:(id)sender
{
	GuessTagsSheet *sheet;
	
	@try {
		sheet = [[GuessTagsSheet alloc] init];
		[sheet setDelegate:self];
		[sheet showSheet];
		
		// TODO: How do I avoid a memory leak here?  For some reason sheet is being autoreleased while it is being displayed
		//[sheet autorelease];
	}
	
	@catch(NSException *exception) {
		NSAlert		*alert;
		
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText:NSLocalizedStringFromTable(@"Your Tag installation appears to be incomplete.", @"Errors", @"")];
		[alert setInformativeText:[exception reason]];
		[alert setAlertStyle:NSInformationalAlertStyle];
		
		[alert runModal];
	}
}

- (void) setValue:(NSString *)value forTag:(NSString *)tag
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSUndoManager			*undoManager		= [self undoManager];
	
	[self willChangeValueForKey:@"tags"];
	[undoManager beginUndoGrouping];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		[current setValue:value forTag:tag];
	}
	[undoManager endUndoGrouping];
	[self didChangeValueForKey:@"tags"];
}

- (void) addValue:(NSString *)value forTag:(NSString *)tag
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSUndoManager			*undoManager		= [self undoManager];
	
	[self willChangeValueForKey:@"tags"];
	[undoManager beginUndoGrouping];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		[current addValue:value forTag:tag];
	}
	[undoManager endUndoGrouping];
	[self didChangeValueForKey:@"tags"];
}

- (void) updateTag:(NSString *)tag withValue:(NSString *)currentValue toValue:(NSString *)newValue
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSUndoManager			*undoManager		= [self undoManager];
	
	[self willChangeValueForKey:@"tags"];
	[undoManager beginUndoGrouping];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		[current updateTag:tag withValue:currentValue toValue:newValue];
	}
	[undoManager endUndoGrouping];
	[self didChangeValueForKey:@"tags"];
}

- (void) renameTag:(NSString *)currentTag withValue:(NSString *)currentValue toTag:(NSString *)newTag
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSUndoManager			*undoManager		= [self undoManager];
	
	[self willChangeValueForKey:@"tags"];
	[undoManager beginUndoGrouping];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		[current renameTag:currentTag withValue:currentValue toTag:newTag];
	}
	[undoManager endUndoGrouping];
	[self didChangeValueForKey:@"tags"];
}

- (void) guessTagsUsingPattern:(NSString *)pattern
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSUndoManager			*undoManager		= [self undoManager];
	
	[self willChangeValueForKey:@"tags"];
	[undoManager beginUndoGrouping];
	enumerator = [[_filesController selectedObjects] objectEnumerator];
	while((current = [enumerator nextObject])) {
		[current guessTagsUsingPattern:pattern];
	}
	[undoManager endUndoGrouping];
	[self didChangeValueForKey:@"tags"];
}

- (void) tableViewSelectionDidChange:(NSNotification *)aNotification
{
	NSEnumerator	*enumerator;
	NSString		*key;
	
	[self tagsChanged];

	enumerator = [_validKeys objectEnumerator];
	while((key = [enumerator nextObject])) {
		[self willChangeValueForKey:key];
		[self didChangeValueForKey:key];
	}
}

- (id) valueForKey:(NSString *)key
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	
	if([_validKeys containsObject:key]) {
		NSArray					*reverseMappedKeys;
		NSString				*currentValue;
		NSString				*lastValue;
		NSColor					*markerColor;
		BOOL					firstTime;
		
		enumerator		= [[_filesController selectedObjects] objectEnumerator];
		currentValue	= nil;
		lastValue		= nil;
		firstTime		= YES;
		
		while((current = [enumerator nextObject])) {
			reverseMappedKeys = [[current tagMapping] allKeysForObject:key];
			
			if(0 < [reverseMappedKeys count]) {
				currentValue = [current valueForTag:[reverseMappedKeys objectAtIndex:0]];
				
				if(NO == firstTime && ((nil != currentValue || nil != lastValue) && NO == [currentValue isEqualToString:lastValue])) {
										
					// Special case for non-text field
					if([key isEqualToString:@"compilation"]) {
						return [NSNumber numberWithInt:NSMixedState];
					}

					markerColor = [NSUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] dataForKey:@"multipleValuesMarkerColor"]];
					[[self valueForKey:[NSString stringWithFormat:@"%@TextField", key]] setBackgroundColor:markerColor];

					return [[NSUserDefaults standardUserDefaults] stringForKey:@"multipleValuesDescription"];
				}
				
				lastValue = currentValue;
				firstTime = NO;
			}
		}

		if(NO == [key isEqualToString:@"compilation"]) {
			[[self valueForKey:[NSString stringWithFormat:@"%@TextField", key]] setBackgroundColor:[NSColor whiteColor]];
		}
		
		return lastValue;
	}
	else if([key isEqualToString:@"tags"]) {
		NSEnumerator			*tagEnumerator;
		NSDictionary			*currentTag;
		NSArray					*currentValue;
		NSArray					*lastValue;
		NSMutableArray			*result;
		BOOL					firstTime;

		enumerator		= [[_filesController selectedObjects] objectEnumerator];
		currentValue	= nil;
		lastValue		= nil;
		result			= nil;
		firstTime		= YES;
		
		while((current = [enumerator nextObject])) {
			currentValue = [current valueForKey:@"tags"];
			
			if(firstTime) {
				// Make a deep copy so the actual file's tags are not modified
				result			= [[NSMutableArray alloc] initWithCapacity:[currentValue count]];
				tagEnumerator	= [currentValue objectEnumerator];
				while((currentTag = [tagEnumerator nextObject])) {
					[result addObject:[[currentTag mutableCopy] autorelease]];
				}
			}
			
			if(NO == firstTime && NO == [currentValue isEqual:lastValue]) {
				// Winnow the result to contain only tags that match in every file
				tagEnumerator = [result objectEnumerator];
				
				while((currentTag = [tagEnumerator nextObject])) {
					if(NO == [currentValue containsObject:currentTag]) {
						[result removeObject:currentTag];
					}
				}
			}
			
			lastValue = currentValue;
			firstTime = NO;
		}
		
		return [result autorelease];
			
	}
	else {
		return [super valueForKey:key];
	}	
}

- (void) setValue:(id)value forKey:(NSString *)key
{
	NSEnumerator			*enumerator;
	KeyValueTaggedFile		*current;
	NSArray					*reverseMappedKeys;
	NSUndoManager			*undoManager		= [self undoManager];
	NSString				*stringValue;

	if([_validKeys containsObject:key]) {
		enumerator = [[_filesController selectedObjects] objectEnumerator];
		[self willChangeValueForKey:@"tags"];
		[undoManager beginUndoGrouping];
		while((current = [enumerator nextObject])) {
			
			reverseMappedKeys = [[current tagMapping] allKeysForObject:key];

			if(0 < [reverseMappedKeys count]) {				
				stringValue = ([value isKindOfClass:[NSString class]] ? (NSString *)value : ([value respondsToSelector:@selector(stringValue)] ? [value stringValue] : nil));
				[current setValue:stringValue forTag:[reverseMappedKeys objectAtIndex:0]];
			}
		}
		[undoManager endUndoGrouping];
		[self didChangeValueForKey:@"tags"];

		if(NO == [key isEqualToString:@"compilation"]) {
			[[self valueForKey:[NSString stringWithFormat:@"%@TextField", key]] setBackgroundColor:[NSColor whiteColor]];
		}
	}
	else {
		[super setValue:value forKey:key];
	}	
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	switch([menuItem tag]) {
		case kSaveMenuItemTag:
		case kRevertMenuItemTag:
			return [self selectionDirty];
			break;
			
		case kOpenMenuItemTag:
		case kToggleDrawerMenuItemTag:
			return YES;
			break;
			
		case kSelectNextMenuItemTag:
			return [_filesController canSelectNext];
			break;
			
		case kSelectPreviousMenuItemTag:
			return [_filesController canSelectPrevious];
			break;

		case kSelectAllFilesMenuItemTag:
			return (0 != [self openFileCount]);
			break;
			
		case kBasicTabMenuItemTag:
		case kAdvancedTabMenuItemTag:
		case kTabularTabMenuItemTag:
			return YES;
			break;
			
		case kNewTagMenuItemTag:
		case kGuessTagsMenuItemTag:
			return (0 < [self selectedFileCount]);
			break;

		case kDeleteTagMenuItemTag:
			return ([[[_tabView selectedTabViewItem] identifier] isEqualToString:@"advanced"] && 0 < [[_tagsController selectedObjects] count]);
			break;
			
		default:
			return [super validateMenuItem:menuItem];
			break;
	}
}

#pragma mark UKFileWatcher delegate method

-(void) watcher:(id<UKFileWatcher>)kq receivedNotification:(NSString*)nm forPath:(NSString*)fpath
{
	NSAlert		*alert			= nil;
	BOOL		removeFile		= NO;
	
	if([nm isEqualToString:UKFileWatcherRenameNotification]) {
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"The name of document \"%@\" has changed.", @"Errors", @""), [fpath lastPathComponent]]];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Your changes have been lost.", @"Errors", @"")];
		[alert setAlertStyle:NSWarningAlertStyle];
		
		[alert runModal];

		removeFile = YES;
	}
	else if([nm isEqualToString:UKFileWatcherDeleteNotification]) {
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"The document \"%@\" has been deleted.", @"Errors", @""), [fpath lastPathComponent]]];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Your changes have been lost.", @"Errors", @"")];
		[alert setAlertStyle:NSWarningAlertStyle];
		
		[alert runModal];
		
		removeFile = YES;
	}
	else if([nm isEqualToString:UKFileWatcherAccessRevocationNotification]) {
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"The document \"%@\" is no longer accessible.", @"Errors", @""), [fpath lastPathComponent]]];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Your changes have been lost.", @"Errors", @"")];
		[alert setAlertStyle:NSWarningAlertStyle];
		
		[alert runModal];
		
		removeFile = YES;
	}
	else if([nm isEqualToString:UKFileWatcherAttributeChangeNotification] || [nm isEqualToString:UKFileWatcherSizeIncreaseNotification]) {
		NSEnumerator			*enumerator;
		NSString				*key;
		int						result;
						
		alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Keep Tag Version", @"General", @"")];
		[alert addButtonWithTitle:NSLocalizedStringFromTable(@"Revert", @"General", @"")];
		[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"The document \"%@\" has changed.  What do you want to do?", @"General", @""), [fpath lastPathComponent]]];
		[alert setInformativeText:NSLocalizedStringFromTable(@"Your changes will be lost if you choose to revert the document.", @"General", @"")];
		[alert setAlertStyle:NSInformationalAlertStyle];
		
		result = [alert runModal];
		switch(result) {
			case NSAlertSecondButtonReturn:
				@try {
					KeyValueTaggedFile		*file		= [_filesController findFile:fpath];
					if(nil != file) {
						[self willChangeValueForKey:@"tags"];
						[file revert];
						[self didChangeValueForKey:@"tags"];
						
						enumerator = [_validKeys objectEnumerator];
						while((key = [enumerator nextObject])) {
							[self willChangeValueForKey:key];
							[self didChangeValueForKey:key];
						}
					}					
				}
				@catch(NSException *exception) {
					alert = [[[NSAlert alloc] init] autorelease];
					[alert addButtonWithTitle:NSLocalizedStringFromTable(@"OK", @"General", @"")];
					[alert setMessageText:[NSString stringWithFormat:NSLocalizedStringFromTable(@"An error occurred while reverting the document \"%@\".", @"Errors", @""), [fpath lastPathComponent]]];
					[alert setInformativeText:[exception reason]];
					[alert setAlertStyle:NSInformationalAlertStyle];
					[alert runModal];
				}
				break;
		}
	}
	
	// Remove file if it was renamed, deleted or is inaccessible
	if(removeFile) {
		KeyValueTaggedFile	*file	= [_filesController findFile:fpath];
		if(nil != file) {
			[_filesController removeObject:file];
		}
		
		[[UKKQueue sharedFileWatcher] removePath:fpath];
	}
}

@end