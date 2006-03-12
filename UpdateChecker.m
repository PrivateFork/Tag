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

#import "UpdateChecker.h"

static UpdateChecker *sharedController = nil;

@implementation UpdateChecker

+ (UpdateChecker *) sharedController
{
	@synchronized(self) {
		if(nil == sharedController) {
			sharedController = [[self alloc] init];
		}
	}
	return sharedController;
}

+ (id) allocWithZone:(NSZone *)zone
{
    @synchronized(self) {
        if(nil == sharedController) {
            return [super allocWithZone:zone];
        }
    }
    return sharedController;
}

- (id)				copyWithZone:(NSZone *)zone					{ return self; }
- (id)				retain										{ return self; }
- (unsigned)		retainCount									{ return UINT_MAX;  /* denotes an object that cannot be released */ }
- (void)			release										{ /* do nothing */ }
- (id)				autorelease									{ return self; }
- (BOOL)			checkInProgress								{ return _checkInProgress; }
- (void)			setCheckInProgress:(BOOL)checkInProgress	{ _checkInProgress = checkInProgress; }

- (id) init
{
	if((self = [super initWithWindowNibName:@"UpdateChecker"])) {
		_socket = [[MacPADSocket alloc] init];
		[_socket setDelegate:self];
		
		[self setCheckInProgress:NO];
		
		return self;
	}
	return nil;
}

- (void) dealloc
{
	[_socket release];
	[super dealloc];
}

- (void) windowDidLoad
{
	[self setShouldCascadeWindows:NO];
	[self setWindowFrameAutosaveName:@"UpdateChecker"];	
	[[self window] setExcludedFromWindowsMenu:YES];
}

- (void) checkForUpdate:(BOOL)showWindow
{
	if(showWindow) {
		[self showWindow:self];	
	}
	
	[self setCheckInProgress:YES];
	[_socket performCheck];
}

- (void) macPADErrorOccurred:(NSNotification *) aNotification
{
	NSWindow *updateWindow = [self window];

	[self setCheckInProgress:NO];

	if([updateWindow isVisible]) {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle: NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText: NSLocalizedStringFromTable(@"An error occurred while checking for a newer version of Tag.", @"Errors", @"")];
		[alert setInformativeText: [[aNotification userInfo] objectForKey:MacPADErrorMessage]];
		[alert setAlertStyle: NSWarningAlertStyle];
		
		[alert beginSheetModalForWindow:updateWindow modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
	}
}

- (void) macPADCheckFinished:(NSNotification *)aNotification
{
	NSWindow *updateWindow = [self window];
	
	[self setCheckInProgress:NO];

	// Suppress up-to-date alert if our window isn't visible (called by ApplicationDelegate at startup)
	if(kMacPADResultNoNewVersion == [[[aNotification userInfo] objectForKey:MacPADErrorCode] intValue] && [updateWindow isVisible]) {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert addButtonWithTitle: NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert setMessageText: NSLocalizedStringFromTable(@"Tag is up-to-date.", @"General", @"")];
		[alert setInformativeText: NSLocalizedStringFromTable(@"You are running the current version of Tag.", @"General", @"")];

		[alert setAlertStyle: NSInformationalAlertStyle];
		
		[alert beginSheetModalForWindow:updateWindow modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
	}
	else if(kMacPADResultNewVersion == [[[aNotification userInfo] objectForKey:MacPADErrorCode] intValue]) {
		NSAlert		*alert	= [[[NSAlert alloc] init] autorelease];
		
		[alert addButtonWithTitle: NSLocalizedStringFromTable(@"OK", @"General", @"")];
		[alert addButtonWithTitle: NSLocalizedStringFromTable(@"More Info", @"General", @"")];
		[alert addButtonWithTitle: NSLocalizedStringFromTable(@"Download", @"General", @"")];
		
		[alert setMessageText: NSLocalizedStringFromTable(@"A newer version of Tag is available.", @"General", @"")];
		[alert setInformativeText: [NSString stringWithFormat:NSLocalizedStringFromTable(@"Tag %@ is available for download.", @"General", @""), [_socket newVersion]]];

		[alert setAlertStyle: NSInformationalAlertStyle];

		if([updateWindow isVisible]) {
			[alert beginSheetModalForWindow:updateWindow modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
		}
		else {
			switch([alert runModal]) {
				case NSAlertFirstButtonReturn:		; /* do nothing */																			break;
				case NSAlertSecondButtonReturn:		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[_socket productPageURL]]];		break;
				case NSAlertThirdButtonReturn:		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[_socket productDownloadURL]]]; break;
			}
		}
	}
}

- (void) alertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSWindow *updateWindow = [self window];
	
	switch(returnCode) {
		case NSAlertFirstButtonReturn:		; /* do nothing */																			break;
		case NSAlertSecondButtonReturn:		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[_socket productPageURL]]];		break;
		case NSAlertThirdButtonReturn:		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[_socket productDownloadURL]]]; break;
	}

	if([updateWindow isVisible]) {
		[updateWindow orderOut:self];
	}
}

@end
