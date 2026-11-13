#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

#include "lethebar_native.h"

using namespace godot;

LethebarNative *LethebarNative::instance = nullptr;
std::string LethebarNative::pending_open;

static NSString *to_ns(const String &value) {
	return [NSString stringWithUTF8String:value.utf8().get_data()];
}

static UIViewController *root_view_controller() {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.isKeyWindow && window.rootViewController) {
				return window.rootViewController;
			}
		}
	}
	return UIApplication.sharedApplication.keyWindow.rootViewController;
}

// The picker outlives the call that opened it, so one delegate stays alive for
// the lifetime of the process.
@interface LethebarPicker : NSObject <UIDocumentPickerDelegate>
@end

// The alert's text field forwards Return to this object, so a phone keyboard's
// Go key behaves like the confirm button.
@interface LethebarField : NSObject <UITextFieldDelegate>
@property (nonatomic, weak) UIAlertController *alert;
@property (nonatomic, copy) NSString *pasteLabel;
@end

@implementation LethebarField

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	NSString *text = field.text ?: @"";
	[self.alert dismissViewControllerAnimated:YES completion:nil];
	LethebarNative::emit_url(String::utf8(text.UTF8String));
	return NO;
}

- (UIMenu *)textField:(UITextField *)textField
	editMenuForCharactersInRange:(NSRange)range
	suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions API_AVAILABLE(ios(16.0)) {
	// The system menu says Paste and AutoFill in the phone's language. The app
	// has its own language switch, so the menu is replaced with the one word the
	// app already knows how to say.
	__weak UITextField *field = textField;
	NSString *label = self.pasteLabel.length ? self.pasteLabel : @"Paste";
	UIAction *paste = [UIAction actionWithTitle:label
		image:nil
		identifier:nil
		handler:^(__kindof UIAction *action) {
			NSString *text = UIPasteboard.generalPasteboard.string;
			if (text.length > 0) {
				[field insertText:text];
			}
		}];
	return [UIMenu menuWithTitle:@"" children:@[paste]];
}

@end

static LethebarField *field_delegate = nil;

static LethebarPicker *picker_delegate = nil;

// Godot's delegate receives a document URL and hands it to a service that
// ignores it. Wrapping the delegate's three entry points is the smallest way to
// give the URL to GDScript without rebuilding the engine.
static BOOL (*original_did_finish)(id, SEL, UIApplication *, NSDictionary *) = nil;
static BOOL (*original_open_url)(id, SEL, UIApplication *, NSURL *, NSDictionary *) = nil;
static void (*original_scene_open)(id, SEL, UIScene *, NSSet<UIOpenURLContext *> *) = nil;

static void capture_url(NSURL *url) {
	if (!url || !url.isFileURL) {
		return;
	}
	LethebarNative::emit_open(String::utf8(url.path.UTF8String));
}

static BOOL hooked_did_finish(id self, SEL _cmd, UIApplication *app, NSDictionary *options) {
	capture_url(options[UIApplicationLaunchOptionsURLKey]);
	return original_did_finish ? original_did_finish(self, _cmd, app, options) : YES;
}

static BOOL hooked_open_url(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *options) {
	capture_url(url);
	return original_open_url ? original_open_url(self, _cmd, app, url, options) : YES;
}

static void hooked_scene_open(id self, SEL _cmd, UIScene *scene, NSSet<UIOpenURLContext *> *contexts) {
	if (original_scene_open) {
		original_scene_open(self, _cmd, scene, contexts);
	}
	for (UIOpenURLContext *context in contexts) {
		capture_url(context.URL);
	}
}

static void replace_method(id target, SEL selector, IMP replacement, IMP *original) {
	if (target == nil) {
		return;
	}
	Method method = class_getInstanceMethod([target class], selector);
	if (method == nil) {
		return;
	}
	*original = method_getImplementation(method);
	method_setImplementation(method, replacement);
}

void godot::lethebar_install_open_url_hook() {
	static bool installed = false;
	if (installed) {
		return;
	}
	id delegate = UIApplication.sharedApplication.delegate;
	if (delegate == nil) {
		return;
	}
	installed = true;
	replace_method(delegate, @selector(application:didFinishLaunchingWithOptions:), (IMP)hooked_did_finish, (IMP *)&original_did_finish);
	replace_method(delegate, @selector(application:openURL:options:), (IMP)hooked_open_url, (IMP *)&original_open_url);
	replace_method(delegate, @selector(scene:openURLContexts:), (IMP)hooked_scene_open, (IMP *)&original_scene_open);
}

@implementation LethebarPicker

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *url = urls.firstObject;
	if (!url) {
		LethebarNative::emit_zip_cancelled();
		return;
	}
	[url startAccessingSecurityScopedResource];
	NSFileManager *files = NSFileManager.defaultManager;
	NSURL *documents = [files URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
	NSURL *directory = [documents URLByAppendingPathComponent:@"Imported" isDirectory:YES];
	[files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
	NSURL *destination = [directory URLByAppendingPathComponent:url.lastPathComponent];
	[files removeItemAtURL:destination error:nil];
	NSError *error = nil;
	BOOL copied = [files copyItemAtURL:url toURL:destination error:&error];
	[url stopAccessingSecurityScopedResource];
	if (copied) {
		LethebarNative::emit_zip(String::utf8(destination.path.UTF8String));
	} else {
		LethebarNative::emit_zip_cancelled();
	}
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	LethebarNative::emit_zip_cancelled();
}

@end

LethebarNative::LethebarNative() {
	instance = this;
	if (!pending_open.empty()) {
		String path = String::utf8(pending_open.c_str());
		pending_open.clear();
		emit_signal("url_opened", path);
	}
}

LethebarNative::~LethebarNative() {
	if (instance == this) {
		instance = nullptr;
	}
}

void LethebarNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("available"), &LethebarNative::available);
	ClassDB::bind_method(D_METHOD("ask_for_url", "title", "message", "placeholder", "confirm", "cancel", "initial", "paste"), &LethebarNative::ask_for_url);
	ClassDB::bind_method(D_METHOD("pick_zip"), &LethebarNative::pick_zip);
	ClassDB::bind_method(D_METHOD("download", "url"), &LethebarNative::download);

	ADD_SIGNAL(MethodInfo("url_entered", PropertyInfo(Variant::STRING, "url")));
	ADD_SIGNAL(MethodInfo("url_cancelled"));
	ADD_SIGNAL(MethodInfo("zip_picked", PropertyInfo(Variant::STRING, "path")));
	ADD_SIGNAL(MethodInfo("zip_cancelled"));
	ADD_SIGNAL(MethodInfo("url_opened", PropertyInfo(Variant::STRING, "path")));
	ADD_SIGNAL(MethodInfo("downloaded", PropertyInfo(Variant::STRING, "path")));
	ADD_SIGNAL(MethodInfo("download_failed", PropertyInfo(Variant::STRING, "reason")));
}

bool LethebarNative::available() const {
	return true;
}

void LethebarNative::ask_for_url(const String &title, const String &message, const String &placeholder, const String &confirm, const String &cancel, const String &initial, const String &paste) {
	NSString *title_text = to_ns(title);
	NSString *message_text = to_ns(message);
	NSString *placeholder_text = to_ns(placeholder);
	NSString *confirm_text = to_ns(confirm);
	NSString *cancel_text = to_ns(cancel);
	NSString *initial_text = to_ns(initial);
	NSString *paste_text = to_ns(paste);

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title_text
																 message:message_text
														  preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = initial_text;
		field.placeholder = placeholder_text;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
		field.keyboardType = UIKeyboardTypeURL;
		field.returnKeyType = UIReturnKeyGo;
		field.clearButtonMode = UITextFieldViewModeWhileEditing;
		if (!field_delegate) {
			field_delegate = [[LethebarField alloc] init];
		}
		field_delegate.alert = alert;
		field_delegate.pasteLabel = paste_text;
		field.delegate = field_delegate;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:confirm_text
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
												UITextField *field = alert.textFields.firstObject;
												LethebarNative::emit_url(field ? String::utf8(field.text.UTF8String) : String());
											}]];
	[alert addAction:[UIAlertAction actionWithTitle:cancel_text
											  style:UIAlertActionStyleCancel
											handler:^(UIAlertAction *action) {
												LethebarNative::emit_url_cancelled();
											}]];
	[root_view_controller() presentViewController:alert animated:YES completion:nil];
}

void LethebarNative::pick_zip() {
	if (!picker_delegate) {
		picker_delegate = [[LethebarPicker alloc] init];
	}
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
			initForOpeningContentTypes:@[ UTTypeZIP ]];
	picker.delegate = picker_delegate;
	picker.allowsMultipleSelection = NO;
	[root_view_controller() presentViewController:picker animated:YES completion:nil];
}

void LethebarNative::emit_url(const String &url) {
	if (instance) {
		instance->emit_signal("url_entered", url);
	}
}

void LethebarNative::emit_url_cancelled() {
	if (instance) {
		instance->emit_signal("url_cancelled");
	}
}

void LethebarNative::emit_zip(const String &path) {
	if (instance) {
		instance->emit_signal("zip_picked", path);
	}
}

void LethebarNative::emit_zip_cancelled() {
	if (instance) {
		instance->emit_signal("zip_cancelled");
	}
}

void LethebarNative::emit_open(const String &path) {
	if (instance) {
		instance->emit_signal("url_opened", path);
	} else {
		pending_open = path.utf8().get_data();
	}
}

void LethebarNative::emit_downloaded(const String &path) {
	if (instance) {
		instance->emit_signal("downloaded", path);
	}
}

void LethebarNative::emit_download_failed(const String &reason) {
	if (instance) {
		instance->emit_signal("download_failed", reason);
	}
}

void LethebarNative::download(const String &url) {
	NSString *address = [NSString stringWithUTF8String:url.utf8().get_data()];
	NSURL *target = [NSURL URLWithString:address];
	if (target == nil || target.scheme.length == 0) {
		emit_download_failed("not a URL");
		return;
	}
	NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
		downloadTaskWithURL:target
		completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
			if (error != nil || location == nil) {
				NSString *why = error != nil ? error.localizedDescription : @"no file";
				dispatch_async(dispatch_get_main_queue(), ^{
					LethebarNative::emit_download_failed(String::utf8(why.UTF8String));
				});
				return;
			}
			NSInteger status = [(NSHTTPURLResponse *)response statusCode];
			if (status != 200) {
				String why = String("HTTP ") + String::num_int64(status);
				dispatch_async(dispatch_get_main_queue(), ^{
					LethebarNative::emit_download_failed(why);
				});
				return;
			}
			NSString *name = target.lastPathComponent;
			if (name.length == 0) {
				name = @"package.zip";
			}
			NSString *dest = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
			NSFileManager *files = [NSFileManager defaultManager];
			[files removeItemAtPath:dest error:nil];
			NSError *move = nil;
			if (![files moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:&move]) {
				NSString *why = move != nil ? move.localizedDescription : @"could not keep the file";
				dispatch_async(dispatch_get_main_queue(), ^{
					LethebarNative::emit_download_failed(String::utf8(why.UTF8String));
				});
				return;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				LethebarNative::emit_downloaded(String::utf8(dest.UTF8String));
			});
		}];
	[task resume];
}
