#import "CDVHostedWebApp.h"
#import <Cordova/CDV.h>
#import "CDVConnection.h"

static NSString* const IOS_PLATFORM = @"ios";
static NSString* const DEFAULT_PLUGIN_MODE = @"client";
static NSString* const DEFAULT_CORDOVA_BASE_URL = @"";

@interface CDVHostedWebApp ()

@property NSString *manifestError;
@property NSURL *failedURL;

@end

@implementation CVDWebViewNotificationDelegate

- (void)webViewDidStartLoad:(UIWebView*)theWebView {
    [self.wrappedDelegate webViewDidStartLoad: theWebView];

    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kCDVHostedWebAppWebViewDidStartLoad object:theWebView]];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kCDVHostedWebAppWebViewShouldStartLoadWithRequest object:request]];

    return [self.wrappedDelegate webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self.wrappedDelegate webViewDidFinishLoad:webView];

    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kCDVHostedWebAppWebViewDidFinishLoad object:webView]];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    [self.wrappedDelegate webView:webView didFailLoadWithError:error];

    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kCDVHostedWebAppWebViewDidFailLoadWithError object:error]];
}

@end

@implementation CDVHostedWebApp

@synthesize manifest;

static NSString * const defaultManifestFileName = @"manifest.json";

- (void)pluginInitialize
{
    [super pluginInitialize];

    // observe notifications from webview when page starts loading
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(webViewDidStartLoad:)
                                                 name:kCDVHostedWebAppWebViewDidStartLoad
                                               object:nil];

    // observe notifications from webview when page starts loading
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(webViewDidFinishLoad:)
                                                 name:kCDVHostedWebAppWebViewDidFinishLoad
                                               object:nil];

    // observe notifications from webview when page fails loading
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didWebViewFailLoadWithError:)
                                                 name:kCDVHostedWebAppWebViewDidFailLoadWithError
                                               object:nil];

    // no connection errors on startup
    self.failedURL = nil;

    // load the W3C manifest
    manifest = [self loadManifestFile:nil];

    // set the webview delegate to notify navigation events
    notificationDelegate = [[CVDWebViewNotificationDelegate alloc] init];
    notificationDelegate.wrappedDelegate = self.webView.delegate;
    [self.webView setDelegate:notificationDelegate];
}

// loads the specified W3C manifest
-(void) loadManifest:(CDVInvokedUrlCommand *)command {

    CDVPluginResult* pluginResult = nil;
    NSString* manifestFileName = [command.arguments objectAtIndex:0];

    manifest = [self loadManifestFile:manifestFileName];
    if (self.manifest != nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:self.manifest];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:self.manifestError];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// returns the currently loaded manifest
-(void) getManifest:(CDVInvokedUrlCommand *)command {

    CDVPluginResult* pluginResult = nil;
    if (self.manifest != nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:self.manifest];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:self.manifestError];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

-(void) injectPluginScript:(CDVInvokedUrlCommand *)command {
    
    NSArray* scriptList = @[[command.arguments objectAtIndex:0]];
    BOOL result = [self injectScripts: scriptList];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// loads a manifest file and parses it
-(NSDictionary *) loadManifestFile:(NSString *)manifestFileName {

    self.manifestError = nil;

    if (manifestFileName == nil) {
        manifestFileName = defaultManifestFileName;
    }

    NSString* filePath = [self.commandDelegate pathForResource:manifestFileName];
    if (filePath == nil) {
        self.manifestError = [NSString stringWithFormat:@"Missing manifest file: %@", manifestFileName];
        return nil;
    }

    NSData *manifestData = [NSData dataWithContentsOfFile:filePath];
    if (manifestData == nil) {
        self.manifestError = [NSString stringWithFormat:@"Error reading manifest file: %@", manifestFileName];
        return nil;
    }

    NSError *error = nil;
    id parsedManifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];

    if (error) {
        /* handle malformed JSON here */
        self.manifestError = [NSString stringWithFormat:@"Error parsing manifest file: %@ - %@", manifestFileName, error];
        return nil;
    }

    if([parsedManifest isKindOfClass:[NSDictionary class]]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kManifestLoadedNotification object:parsedManifest];        
        return parsedManifest;
    }

    /* deserialization is not a dictionary--it probably means an invalid manifest. */
    self.manifestError = [NSString stringWithFormat:@"Invalid or unexpected manifest format: %@", manifestFileName];
    return nil;
}

-(BOOL) injectScripts:(NSArray *)scriptList {
    
    NSString* content = @"";
    for (NSString* scriptName in scriptList)
    {
        NSURL* scriptUrl = [NSURL URLWithString:scriptName relativeToURL:[NSURL URLWithString:@"www/"]];
        NSString* scriptPath = scriptUrl.absoluteString;
        NSError *error = nil;
        NSString* fileContents =  nil;
        if (scriptUrl.scheme == nil)
        {
            fileContents = [NSString stringWithContentsOfFile: [[NSBundle mainBundle] pathForResource: scriptPath ofType:nil] encoding:NSUTF8StringEncoding error:&error];
        }
        else
        {
            fileContents = [NSString stringWithContentsOfURL:scriptUrl encoding:NSUTF8StringEncoding error:&error];
        }
        
        if (error == nil) {
            // prefix with @ sourceURL=<scriptName> comment to make the injected scripts visible in Safari's Web Inspector for debugging purposes
            content = [content stringByAppendingFormat:@"\r\n//@ sourceURL=%@\r\n%@", scriptName, fileContents];
        }
        else {
            NSLog(@"ERROR failed to load script file: '%@'", scriptName);
        }
    }
    
    return[self.webView stringByEvaluatingJavaScriptFromString:content] != nil;
}

- (BOOL) isCordovaEnabled
{
    BOOL enableCordova = NO;
    NSObject* setting = [self.manifest objectForKey:@"mjs_api_access"];
    if (setting != nil && [setting isKindOfClass:[NSArray class]])
    {
        NSArray* accessRules = (NSArray*) setting;
        if (accessRules != nil)
        {
            for (NSDictionary* rule in accessRules)
            {
                if ([self isMatchingRuleForPage:rule withPlatformCheck:YES])
                {
                    setting = [rule objectForKey:@"access"];
                    
                    NSString* access = setting != nil ?
                        [(NSString*)setting stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
                    if (access == nil || [access isEqualToString:@"cordova"])
                    {
                        enableCordova = YES;
                    }
                    else if ([access isEqualToString:@"none"])
                    {
                        return NO;
                    }
                    else
                    {
                        NSLog(@"ERROR unsupported access type '%@' found in mjs_api_access rule.", access);
                    }
                }
            }
        }
    }
    
    return enableCordova;
}

-(BOOL) isMatchingRuleForPage:(NSDictionary*) rule withPlatformCheck: (BOOL) checkPlatform
{
    // ensure rule applies to current platform
    if (checkPlatform)
    {
        BOOL isPlatformMatch = NO;
        NSObject* setting = [rule objectForKey:@"platform"];
        if (setting != nil && [setting isKindOfClass:[NSString class]])
        {
            for (id item in [(NSString*)setting componentsSeparatedByString:@","])
            {
                if ([[item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] caseInsensitiveCompare:IOS_PLATFORM] == NSOrderedSame)
                {
                    isPlatformMatch = YES;
                    break;
                }
            }
            
            if (!isPlatformMatch)
            {
                return NO;
            }
        }
    }
    
    // ensure rule applies to current page
    BOOL isURLMatch = YES;
    NSObject* setting = [rule objectForKey:@"match"];
    if (setting != nil)
    {
        NSArray* match = nil;
        if ([setting isKindOfClass:[NSArray class]])
        {
            match = (NSArray*) setting;
        }
        else if ([setting isKindOfClass:[NSString class]])
        {
            match = [NSArray arrayWithObjects:setting, nil];
        }
        
        if (match != nil)
        {
            CDVWhitelist *whitelist = [[CDVWhitelist alloc] initWithArray:match];
            NSURL* url = self.webView.request.URL;
            isURLMatch = [whitelist URLIsAllowed:url];
        }
    }
    
    return isURLMatch;
}

// Handles notifications from the webview delegate whenever a page starts loading.
- (void)webViewDidStartLoad:(NSNotification*)notification
{
    if ([[notification name] isEqualToString:kCDVHostedWebAppWebViewDidStartLoad]) {
        NSLog (@"Received a navigation start notification.");
        self.failedURL = nil;
    }
}

// Handles notifications from the webview delegate whenever a page finishes loading.
- (void)webViewDidFinishLoad:(NSNotification*)notification
{
    if ([[notification name] isEqualToString:kCDVHostedWebAppWebViewDidFinishLoad]) {
        NSLog (@"Received a navigation completed notification.");
        
        // inject Cordova
        if ([self isCordovaEnabled])
        {
            NSObject* setting = [self.manifest objectForKey:@"mjs_cordova"];
            if (setting == nil && ![setting isKindOfClass:[NSDictionary class]])
            {
                setting = [[NSDictionary alloc] init];
            }
            
            NSDictionary* cordova = (NSDictionary*) setting;
            
            setting = [cordova objectForKey:@"plugin_mode"];
            NSString* pluginMode = (setting != nil && [setting isKindOfClass:[NSString class]])
                ? [(NSString*)setting stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                : DEFAULT_PLUGIN_MODE;
            
            setting = [cordova objectForKey:@"base_url"];
            NSString* cordovaBaseUrl = (setting != nil && [setting isKindOfClass:[NSString class]])
                ? [(NSString*)setting stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                : DEFAULT_CORDOVA_BASE_URL;
            
            if (![cordovaBaseUrl hasSuffix:@"/"])
            {
                cordovaBaseUrl = [cordovaBaseUrl stringByAppendingString:@"/"];
            }
            
            NSString* javascript = [NSString stringWithFormat:@"window.hostedWebApp = { 'platform': '%@', 'pluginMode': '%@', 'cordovaBaseUrl': '%@'};", IOS_PLATFORM, pluginMode, cordovaBaseUrl];
            [self.webView stringByEvaluatingJavaScriptFromString:javascript];
            
            NSMutableArray* scripts = [[NSMutableArray alloc] init];
            if ([pluginMode isEqualToString:@"client"])
            {
                [scripts addObject: @"cordova.js"];
            }
            
            [scripts addObject: @"hostedapp-bridge.js"];
            [self injectScripts: scripts];
        }
        
        // inject custom scripts
        NSObject* setting = [self.manifest objectForKey:@"mjs_import_scripts"];
        if (setting != nil && [setting isKindOfClass:[NSArray class]])
        {
            NSArray* customScripts = (NSArray*) setting;
            if (customScripts != nil && customScripts.count > 0)
            {
                for (NSDictionary* item in customScripts)
                {
                    if ([self isMatchingRuleForPage:item withPlatformCheck:NO])
                    {
                        NSString* source = [item valueForKey:@"src"];
                        [self injectScripts: @[source]];
                    }
                }
            }
        }
    }
}

// Handles notifications from the webview delegate whenever a page load fails.
- (void)didWebViewFailLoadWithError:(NSNotification*)notification
{
    NSError* error = [notification object];

    if ([[notification name] isEqualToString:kCDVHostedWebAppWebViewDidFailLoadWithError]) {
        NSLog (@"Received a navigation failure notification. error: %@", [error description]);
        if ([error code] == NSURLErrorTimedOut ||
            [error code] == NSURLErrorUnsupportedURL ||
            [error code] == NSURLErrorCannotFindHost ||
            [error code] == NSURLErrorCannotConnectToHost ||
            [error code] == NSURLErrorDNSLookupFailed ||
            [error code] == NSURLErrorNotConnectedToInternet ||
            [error code] == NSURLErrorNetworkConnectionLost) {

            self.failedURL = [NSURL URLWithString:[error.userInfo objectForKey:@"NSErrorFailingURLStringKey"]];
        }
    }
}

@end
