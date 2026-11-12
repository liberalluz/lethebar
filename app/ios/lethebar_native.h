#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

// The only door from GDScript to UIKit: two calls and four signals. Everything
// else stays in the engine, so a package can never reach the system.
class LethebarNative : public Object {
	GDCLASS(LethebarNative, Object)

protected:
	static void _bind_methods();

public:
	LethebarNative();
	~LethebarNative() override;

	bool available() const;
	void ask_for_url(const String &title, const String &message, const String &placeholder, const String &confirm, const String &cancel, const String &initial);
	void pick_zip();

	static void emit_url(const String &url);
	static void emit_url_cancelled();
	static void emit_zip(const String &path);
	static void emit_zip_cancelled();
	static void emit_open(const String &path);

private:
	static LethebarNative *instance;
	static String pending_open;
};

// Installs the hook that hands a document opened in Files or Messages to the
// plugin. Godot's own delegate receives the URL and drops it, so the plugin
// wraps the delegate's methods instead of rebuilding the engine.
void lethebar_install_open_url_hook();

} // namespace godot
