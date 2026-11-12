#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "lethebar_native.h"

using namespace godot;

LethebarNative *LethebarNative::instance = nullptr;

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

static LethebarPicker *picker_delegate = nil;

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
}

LethebarNative::~LethebarNative() {
	if (instance == this) {
		instance = nullptr;
	}
}

void LethebarNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("available"), &LethebarNative::available);
	ClassDB::bind_method(D_METHOD("ask_for_url", "title", "message", "placeholder", "confirm", "cancel"), &LethebarNative::ask_for_url);
	ClassDB::bind_method(D_METHOD("pick_zip"), &LethebarNative::pick_zip);

	ADD_SIGNAL(MethodInfo("url_entered", PropertyInfo(Variant::STRING, "url")));
	ADD_SIGNAL(MethodInfo("url_cancelled"));
	ADD_SIGNAL(MethodInfo("zip_picked", PropertyInfo(Variant::STRING, "path")));
	ADD_SIGNAL(MethodInfo("zip_cancelled"));
}

bool LethebarNative::available() const {
	return true;
}

void LethebarNative::ask_for_url(const String &title, const String &message, const String &placeholder, const String &confirm, const String &cancel) {
	NSString *title_text = to_ns(title);
	NSString *message_text = to_ns(message);
	NSString *placeholder_text = to_ns(placeholder);
	NSString *confirm_text = to_ns(confirm);
	NSString *cancel_text = to_ns(cancel);

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title_text
																 message:message_text
														  preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = placeholder_text;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
		field.keyboardType = UIKeyboardTypeURL;
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
