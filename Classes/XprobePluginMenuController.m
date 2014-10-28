//
//  XprobePluginMenuController.m
//  XprobePlugin
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright (c) 2014 John Holdsworth. All rights reserved.
//

#import "XprobePluginMenuController.h"

#import "XprobeConsole.h"
#import "Xprobe.h"

#import <WebKit/WebKit.h>

XprobePluginMenuController *xprobePlugin;

@interface NSObject(INMethodsUsed)
+ (NSImage *)iconImage_pause;
@end

@interface XprobePluginMenuController()

@property IBOutlet NSMenuItem *xprobeMenu;
@property IBOutlet NSWindow *webWindow;
@property IBOutlet WebView *webView;

@property NSButton *pauseResume;
@property NSTextView *debugger;

@end

@implementation XprobePluginMenuController

+ (void)pluginDidLoad:(NSBundle *)plugin {
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		xprobePlugin = [[self alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:xprobePlugin
                                                 selector:@selector(applicationDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification object:nil];
	});
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if ( ![[NSBundle bundleForClass:[self class]] loadNibNamed:@"XprobePluginMenuController" owner:self topLevelObjects:NULL] )
        if ( [[NSAlert alertWithMessageText:@"Injection Plugin:"
                              defaultButton:@"OK" alternateButton:@"Goto GitHub" otherButton:nil
                  informativeTextWithFormat:@"Could not load interface nib. If problems persist, "
               "please download and build from the sources on GitHub."]
              runModal] == NSAlertAlternateReturn )
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/johnno1962/XprobePlugin"]];

    [self.webWindow setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];

	NSMenu *productMenu = [[[NSApp mainMenu] itemWithTitle:@"Product"] submenu];
    [productMenu addItem:[NSMenuItem separatorItem]];
    [productMenu addItem:self.xprobeMenu];

    [XprobeConsole backgroundConnectionService];
}

- (NSString *)resourcePath {
    return [[NSBundle bundleForClass:[self class]] resourcePath];
}

static __weak id lastKeyWindow;

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ( [menuItem action] == @selector(graph:) )
        return YES;
    else
        return (lastKeyWindow = [NSApp keyWindow]) != nil &&
            [[lastKeyWindow delegate] respondsToSelector:@selector(document)];
}

- (IBAction)load:sender {
    [self findConsole:[lastKeyWindow contentView]];
    if ( [self.pauseResume image] == [[[self.pauseResume target] class] iconImage_pause] )
        [self.pauseResume performClick:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self performSelector:@selector(findLLDB) withObject:nil afterDelay:.5];
}

- (void)findConsole:(NSView *)view {
    for ( NSView *subview in [view subviews] ) {
        if ( [subview isKindOfClass:[NSButton class]] &&
            [(NSButton *)subview action] == @selector(pauseOrResume:) )
            self.pauseResume = (NSButton *)subview;
        if ( [subview class] == NSClassFromString(@"IDEConsoleTextView") )
            self.debugger = (NSTextView *)subview;
        [self findConsole:subview];
    }
}

- (void)findLLDB {

    if ( ![[self.debugger string] hasSuffix:@"(lldb) "] ) {
        [self performSelector:@selector(findLLDB) withObject:nil afterDelay:.2];
        return;
    }

    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    NSString *loader = [NSString stringWithFormat:@"p (void)[[NSBundle bundleWithPath:@\""
                        "%@/XprobeBundle.bundle\"] load]", [self resourcePath]];

    [self keyEvent:loader code:0 after:0.];

    [self performSelector:@selector(forceContinue) withObject:nil afterDelay:.5];
}

- (void)forceContinue {
    if ( [self.pauseResume image] != [[[self.pauseResume target] class] iconImage_pause] ) {
        [self keyEvent:@"c" code:0 after:1];
        [self performSelector:@selector(forceContinue) withObject:nil afterDelay:1];
    }
}

- (void)keyEvent:(NSString *)str code:(unsigned short)code after:(float)delay {
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown location:NSMakePoint(0, 0)
                                 modifierFlags:0 timestamp:0 windowNumber:0 context:0
                                    characters:str charactersIgnoringModifiers:nil
                                     isARepeat:YES keyCode:code];
    [self performSelector:@selector(keyEvent:) withObject:event afterDelay:delay];
    if ( code == 0 )
        [self keyEvent:@"\r" code:36 after:delay+.1];
}

- (void)keyEvent:(NSEvent *)event {
    [[self.debugger window] makeFirstResponder:self.debugger];
    if ( [[self.debugger window] firstResponder] == self.debugger )
        [self.debugger keyDown:event];
}

- (IBAction)xcode:(id)sender {
    lastKeyWindow = [NSApp keyWindow];
    [Xprobe connectTo:"127.0.0.1" retainObjects:YES];
    [Xprobe search:@""];
}

- (IBAction)graph:(id)sender {
    static NSString *DOT_PATH = @"/usr/local/bin/dot";

    if ( !dotConsole ) {
        [self load:self];
        [self.webWindow performSelector:@selector(makeKeyAndOrderFront:) withObject:self afterDelay:10.];
    }
    else if ( sender )
        [self.webWindow makeKeyAndOrderFront:self];
    else if ( ![self.webWindow isVisible] )
        return;

    if ( ![[NSFileManager defaultManager] fileExistsAtPath:DOT_PATH] ) {
        if ( [[NSAlert alertWithMessageText:@"XprobePlugin" defaultButton:@"OK" alternateButton:@"Go to site"
                                otherButton:nil informativeTextWithFormat:@"Object Graphs of your application "
               "can be displayed if you install \"dot\" from http://www.graphviz.org/. An example object graph "
               "from the cocos2d application \"tweejump\" wil be displayed."] runModal] == NSAlertAlternateReturn )
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.graphviz.org/Download_macos.php"]];
    }
    else {
        NSTask *task = [NSTask new];
        task.launchPath = DOT_PATH;
        task.currentDirectoryPath = [self resourcePath];
        task.arguments = @[@"graph.gv", @"-Txdot", @"-ograph-xdot.gv"];

        [task launch];
        [task waitUntilExit];
    }

    self.webWindow.title = [NSString stringWithFormat:@"%@ Object Graph", dotConsole ? dotConsole.package : @"Last"];
    NSURL *url = [NSURL fileURLWithPath:[[self resourcePath] stringByAppendingPathComponent:@"canviz.html"]];
    [[self.webView mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
    //[self.webView.mainFrame.frameView.documentView setWantsLayer:YES];
}

- (void)execJS:(NSString *)js {
    [[self.webView windowScriptObject] evaluateWebScript:js];
}

- (IBAction)graphviz:(id)sender {
    NSString *graph = [[self resourcePath] stringByAppendingPathComponent:@"graph.gv"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:graph]];
}

- (IBAction)graphpng:(id)sender {
    [self execJS:@"$('menus').style.display = 'none';"];
    NSView *view = self.webView.mainFrame.frameView.documentView;
    NSString *graph = [[self resourcePath] stringByAppendingPathComponent:@"graph.png"];

    NSBitmapImageRep *bir = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bir];
    NSData *data = [bir representationUsingType:NSPNGFileType properties:nil];

    [data writeToFile:graph atomically:NO];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:graph]];
    [self execJS:@"$('menus').style.display = 'block';"];
}

- (NSString *)webView:(WebView *)sender runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WebFrame *)frame {
    [dotConsole writeString:prompt];
    [dotConsole writeString:defaultText];
    if ( [prompt isEqualToString:@"open:"] )
        dispatch_after(.1, dispatch_get_main_queue(), ^{
            NSString *scrollToVisble = [NSString stringWithFormat:@"window.scrollTo( 0, $('%@').offsetTop );", defaultText];
            [dotConsole.window makeKeyAndOrderFront:self];
            [dotConsole execJS:scrollToVisble];
        });
    return nil;
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    [[NSAlert alertWithMessageText:@"XprobeConsole" defaultButton:@"OK" alternateButton:nil otherButton:nil
         informativeTextWithFormat:@"JavaScript Alert: %@", message] runModal];
}

- (IBAction)print:sender {
    NSPrintOperation *po=[NSPrintOperation printOperationWithView:self.webView.mainFrame.frameView.documentView];
    [[po printInfo] setOrientation:NSPaperOrientationLandscape];
    //[po setShowPanels:flags];
    [po runOperation];
}

@end

@implementation Xprobe(Seeding)

+ (NSArray *)xprobeSeeds {
    return @[lastKeyWindow];
}

@end

