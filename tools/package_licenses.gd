extends SceneTree
## Packaging metadata extraction only; does not run the application or tests.
func _initialize()->void:
	DirAccess.make_dir_recursive_absolute("res://.tools/package-licenses")
	var license_file:=FileAccess.open("res://.tools/package-licenses/GODOT-LICENSE.txt",FileAccess.WRITE)
	license_file.store_string(Engine.get_license_text());license_file.close()
	var notices:=FileAccess.open("res://.tools/package-licenses/GODOT-THIRD-PARTY-NOTICES.json",FileAccess.WRITE)
	notices.store_string(JSON.stringify({"copyright":Engine.get_copyright_info(),"licenses":Engine.get_license_info()},"  "));notices.close()
	quit()
