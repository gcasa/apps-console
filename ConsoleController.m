#import "ConsoleController.h"
#import "LogEntry.h"

static NSTextField *Label(NSView *parent, NSString *text, NSRect frame)
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
  [label setStringValue:text]; [label setEditable:NO]; [label setSelectable:NO];
  [label setBezeled:NO]; [label setDrawsBackground:NO];
  [parent addSubview:label];
  return label;
}
static NSButton *Button(NSView *parent, NSString *title, NSRect frame, id target, SEL action)
{
  NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
  [button setTitle:title]; [button setTarget:target]; [button setAction:action];
  [parent addSubview:button]; return button;
}

@implementation ConsoleController
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  _entries = [NSMutableArray new]; _visible = [NSMutableArray new]; _pending = [NSMutableData new];
  NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Console"] autorelease];
  [menu addItemWithTitle:_(@"About Console") action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
  [[menu addItemWithTitle:_(@"System Journal") action:@selector(openJournal:) keyEquivalent:@"j"] setTarget:self];
  [[menu addItemWithTitle:_(@"Open Log File…") action:@selector(openFile:) keyEquivalent:@"o"] setTarget:self];
  [[menu addItemWithTitle:_(@"Copy Message") action:@selector(copy:) keyEquivalent:@"c"] setTarget:self];
  [menu addItemWithTitle:_(@"Quit Console") action:@selector(terminate:) keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];

  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 1060, 700)
    styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
    backing:NSBackingStoreBuffered defer:NO];
  [_window setTitle:_(@"Console — System Log")]; [_window setMinSize:NSMakeSize(820, 500)];
  [_window setReleasedWhenClosed:NO]; [_window setFrameAutosaveName:@"ConsoleWindow"];
  NSView *view = [_window contentView];
  _sourceLabel = Label(view, @"SYSTEM JOURNAL", NSMakeRect(16, 662, 490, 24));
  [_sourceLabel setFont:[NSFont boldSystemFontOfSize:16]];
  [_sourceLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  NSButton *journal = Button(view, _(@"System Journal"), NSMakeRect(548, 657, 135, 30), self, @selector(openJournal:));
  NSButton *open = Button(view, _(@"Open Log…"), NSMakeRect(689, 657, 112, 30), self, @selector(openFile:));
  _pause = Button(view, _(@"Pause"), NSMakeRect(807, 657, 112, 30), self, @selector(togglePause:));
  NSButton *clear = Button(view, _(@"Clear"), NSMakeRect(925, 657, 119, 30), self, @selector(clear:));
  for (NSView *button in @[journal, open, _pause, clear]) [button setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];

  NSTextField *label = Label(view, _(@"Search"), NSMakeRect(16, 618, 58, 22));
  [label setAutoresizingMask:NSViewMinYMargin];
  _search = [[[NSTextField alloc] initWithFrame:NSMakeRect(78, 614, 390, 28)] autorelease];
  [_search setDelegate:self]; [_search setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [_search setToolTip:_(@"Find text in messages, processes, or journal metadata (case insensitive)")]; [view addSubview:_search];
  label = Label(view, _(@"Process"), NSMakeRect(482, 618, 65, 22));
  [label setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  _process = [[[NSTextField alloc] initWithFrame:NSMakeRect(552, 614, 205, 28)] autorelease];
  [_process setDelegate:self]; [_process setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [_process setToolTip:_(@"Filter by process name or PID")]; [view addSubview:_process];
  _severity = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(772, 612, 272, 30) pullsDown:NO] autorelease];
  [_severity addItemsWithTitles:@[_(@"All levels"), _(@"Warning and more severe"), _(@"Error and more severe"), _(@"Critical and more severe"), _(@"Info and more severe"), _(@"Debug only")]];
  [_severity setTarget:self]; [_severity setAction:@selector(filterChanged:)];
  [_severity setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin]; [view addSubview:_severity];

  NSSplitView *split = [[[NSSplitView alloc] initWithFrame:NSMakeRect(16, 48, 1028, 551)] autorelease];
  [split setVertical:NO]; [split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 1028, 365)] autorelease];
  [scroll setHasVerticalScroller:YES]; [scroll setHasHorizontalScroller:YES]; [scroll setBorderType:NSBezelBorder];
  _table = [[[NSTableView alloc] initWithFrame:[scroll bounds]] autorelease];
  NSArray *identifiers = @[@"time", @"severity", @"process", @"message"];
  NSArray *titles = @[_(@"Time"), _(@"Level"), _(@"Process"), _(@"Message")];
  CGFloat widths[] = {185, 85, 190, 650};
  for (NSUInteger i = 0; i < [identifiers count]; i++)
    {
      NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[identifiers objectAtIndex:i]] autorelease];
      [[column headerCell] setStringValue:[titles objectAtIndex:i]]; [column setWidth:widths[i]];
      [column setEditable:NO]; [_table addTableColumn:column];
    }
  [_table setDataSource:self]; [_table setDelegate:self]; [_table setRowHeight:23];
  [_table setAllowsEmptySelection:YES]; [scroll setDocumentView:_table]; [split addSubview:scroll];
  NSScrollView *details = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 1028, 180)] autorelease];
  [details setHasVerticalScroller:YES]; [details setBorderType:NSBezelBorder];
  _detail = [[[NSTextView alloc] initWithFrame:[[details contentView] bounds]] autorelease];
  [_detail setEditable:NO]; [_detail setRichText:NO]; [_detail setFont:[NSFont userFixedPitchFontOfSize:12]];
  [_detail setAutoresizingMask:NSViewWidthSizable];
  [[_detail textContainer] setWidthTracksTextView:YES];
  [details setDocumentView:_detail]; [split addSubview:details]; [view addSubview:split];
  [_detail setString:_(@"Select a message to inspect its full text and journal fields.")];
  _status = Label(view, _(@"Connecting…"), NSMakeRect(16, 14, 830, 24));
  [_status setAutoresizingMask:NSViewWidthSizable];
  _follow = Button(view, _(@"Follow newest"), NSMakeRect(874, 12, 170, 28), self, @selector(followChanged:));
  [_follow setButtonType:NSSwitchButton]; [_follow setState:NSOnState]; [_follow setAutoresizingMask:NSViewMinXMargin];
  [_window makeKeyAndOrderFront:nil];
  _refreshTimer = [[NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(refresh:) userInfo:nil repeats:YES] retain];
  [self openJournal:nil];
}
- (void)stopSource
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  if (_output) [center removeObserver:self name:NSFileHandleReadCompletionNotification object:_output];
  if (_errors) [center removeObserver:self name:NSFileHandleReadCompletionNotification object:_errors];
  if (_task && [_task isRunning]) [_task terminate];
  [_output closeFile]; [_errors closeFile];
  [_output release]; _output = nil; [_errors release]; _errors = nil;
  [_task release]; _task = nil; [_pending setLength:0];
}
- (NSString *)executable:(NSString *)name
{
  for (NSString *directory in @[@"/usr/bin", @"/bin", @"/usr/local/bin"])
    {
      NSString *path = [directory stringByAppendingPathComponent:name];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
    }
  return nil;
}
- (void)startSource
{
  [self stopSource];
  [_entries removeAllObjects]; [_visible removeAllObjects]; [_table reloadData];
  [_detail setString:_(@"Select a message to inspect its full text and journal fields.")];
  [_diagnostic release]; _diagnostic = nil; _paused = NO; [_pause setTitle:@"Pause"];
  NSString *executable = [self executable:_journal ? @"journalctl" : @"tail"];
  if (!executable)
    {
      _diagnostic = [_(@"Log reader unavailable. Use Open Log to choose a readable system log.") copy];
      _dirty = YES; return;
    }
  _task = [NSTask new]; [_task setLaunchPath:executable];
  [_task setArguments:_journal ? @[@"--follow", @"--lines=1000", @"--output=json", @"--no-pager", @"--quiet"] : @[@"-n", @"1000", @"-F", @"--", _filePath]];
  NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe];
  [_task setStandardOutput:out]; [_task setStandardError:err];
  [_task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
  _output = [[out fileHandleForReading] retain]; _errors = [[err fileHandleForReading] retain];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(received:) name:NSFileHandleReadCompletionNotification object:_output];
  [center addObserver:self selector:@selector(receivedError:) name:NSFileHandleReadCompletionNotification object:_errors];
  @try { [_task launch]; [_output readInBackgroundAndNotify]; [_errors readInBackgroundAndNotify]; }
  @catch (NSException *exception) { _diagnostic = [[exception reason] copy]; [self stopSource]; }
  _dirty = YES;
}
- (void)openJournal:(id)sender
{
  _journal = YES;
  if (![self executable:@"journalctl"])
    for (NSString *path in @[@"/var/log/syslog", @"/var/log/messages", @"/var/log/system.log"])
      if ([[NSFileManager defaultManager] isReadableFileAtPath:path])
        { _journal = NO; [_filePath release]; _filePath = [path copy]; break; }
  [_sourceLabel setStringValue:_journal ? @"SYSTEM JOURNAL" : _filePath];
  [self startSource];
}
- (void)openFile:(id)sender
{
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setCanChooseDirectories:NO]; [panel setAllowsMultipleSelection:NO];
  if ([panel runModal] != NSOKButton) return;
  NSString *path = [panel filename];
  if (![[NSFileManager defaultManager] isReadableFileAtPath:path])
    { NSRunAlertPanel(_(@"Cannot Read Log"), _(@"Choose a log file you have permission to read."), @"OK", nil, nil); return; }
  [_filePath release]; _filePath = [path copy]; _journal = NO;
  [_sourceLabel setStringValue:_filePath]; [self startSource];
}
- (void)appendLine:(NSData *)data
{
  NSString *line = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
  if (!line) line = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
  if (![line length]) return;
  LogEntry *entry = _journal ? [LogEntry entryWithJournalLine:line] : [LogEntry entryWithTextLine:line];
  if (entry) [_entries addObject:entry];
}
- (void)received:(NSNotification *)notification
{
  if ([notification object] != _output) return;
  NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
  [_pending appendData:data ?: [NSData data]];
  const unsigned char *bytes = [_pending bytes]; NSUInteger start = 0;
  for (NSUInteger i = 0; i < [_pending length]; i++)
    if (bytes[i] == '\n')
      { [self appendLine:[_pending subdataWithRange:NSMakeRange(start, i - start)]]; start = i + 1; }
  if (start) [_pending replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
  if (![data length] && [_pending length]) { [self appendLine:_pending]; [_pending setLength:0]; }
  if ([_pending length] > 4 * 1024 * 1024) { [_pending setLength:0]; [_diagnostic release]; _diagnostic = [_(@"Skipped an oversized log record.") copy]; }
  if ([_entries count] > 10000) [_entries removeObjectsInRange:NSMakeRange(0, [_entries count] - 10000)];
  if ([data length]) [_output readInBackgroundAndNotify];
  else if (!_diagnostic) _diagnostic = [_(@"Log stream ended. Reopen the source to reconnect.") copy];
  _dirty = YES;
}
- (void)receivedError:(NSNotification *)notification
{
  if ([notification object] != _errors) return;
  NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
  if ([data length])
    {
      NSString *message = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
      [_diagnostic release]; _diagnostic = [[message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
      [_errors readInBackgroundAndNotify]; _dirty = YES;
    }
}
- (void)rebuild
{
  NSInteger selected = [_table selectedRow];
  LogEntry *entry = selected >= 0 && selected < (NSInteger)[_visible count] ? [[_visible objectAtIndex:selected] retain] : nil;
  [_visible removeAllObjects];
  NSInteger index = [_severity indexOfSelectedItem]; NSInteger priorities[] = {7, 4, 3, 2, 6, 7};
  for (LogEntry *item in _entries)
    if ([item matchesText:[_search stringValue] process:[_process stringValue] maximumPriority:priorities[index]] && (index != 5 || item.priority == 7)) [_visible addObject:item];
  [_table reloadData];
  NSUInteger position = entry ? [_visible indexOfObjectIdenticalTo:entry] : NSNotFound;
  if (position != NSNotFound) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:position] byExtendingSelection:NO];
  else { [_table deselectAll:nil]; [_detail setString:_(@"Select a message to inspect its full text and journal fields.")]; }
  [entry release];
  if ([_follow state] == NSOnState && [_visible count]) [_table scrollRowToVisible:[_visible count] - 1];
}
- (void)refresh:(id)sender
{
  if (!_dirty) return;
  if (!_paused) { [self rebuild]; _dirty = NO; }
  [_status setStringValue:[NSString stringWithFormat:_(@"%@ · %lu shown / %lu retained%@%@"), _paused ? _(@"Display paused") : _(@"Live"), (unsigned long)[_visible count], (unsigned long)[_entries count], [_entries count] == 10000 ? @" (latest 10,000)" : @"", _diagnostic ? [@" · " stringByAppendingString:_diagnostic] : @""]];
  [_status setToolTip:_diagnostic ?: _(@"Shows logs accessible to your account. The latest 10,000 records are retained.")];
}
- (void)filterChanged:(id)sender { [self rebuild]; _dirty = YES; [self refresh:nil]; }
- (void)controlTextDidChange:(NSNotification *)notification { [self filterChanged:nil]; }
- (void)togglePause:(id)sender { _paused = !_paused; [_pause setTitle:_paused ? _(@"Resume") : @"Pause"]; _dirty = YES; [self refresh:nil]; }
- (void)followChanged:(id)sender { if ([_follow state] == NSOnState && [_visible count]) [_table scrollRowToVisible:[_visible count] - 1]; }
- (void)clear:(id)sender { [_entries removeAllObjects]; [self rebuild]; _dirty = YES; [self refresh:nil]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return [_visible count]; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  LogEntry *entry = [_visible objectAtIndex:row];
  NSString *key = [column identifier];
  if ([key isEqualToString:@"message"])
    return [[entry.message componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" ↵ "];
  return [entry valueForKey:key];
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  NSInteger row = [_table selectedRow];
  if (row >= 0 && row < (NSInteger)[_visible count]) [_detail setString:[[_visible objectAtIndex:row] details]];
}
- (void)copy:(id)sender
{
  if ([_window firstResponder] != _table && [[_window firstResponder] respondsToSelector:@selector(copy:)])
    { [(id)[_window firstResponder] copy:sender]; return; }
  NSInteger row = [_table selectedRow];
  if (row < 0) return;
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
  [pasteboard declareTypes:@[NSStringPboardType] owner:nil];
  [pasteboard setString:[[_visible objectAtIndex:row] details] forType:NSStringPboardType];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification { [_refreshTimer invalidate]; [self stopSource]; }
- (void)dealloc
{
  [self stopSource]; [_refreshTimer invalidate]; [_refreshTimer release];
  [_window release]; [_entries release]; [_visible release]; [_pending release];
  [_filePath release]; [_diagnostic release]; [super dealloc];
}
@end
