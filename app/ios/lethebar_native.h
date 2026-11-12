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
	void ask_for_url(const String &title, const String &message, const String &placeholder, const String &confirm, const String &cancel);
	void pick_zip();

	static void emit_url(const String &url);
	static void emit_url_cancelled();
	static void emit_zip(const String &path);
	static void emit_zip_cancelled();

private:
	static LethebarNative *instance;
};

} // namespace godot
