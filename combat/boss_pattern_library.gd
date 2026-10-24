## 패턴 JSON 로더. {"patterns": {id: BossAttackPattern}, "sequence": [id, ...]} 를 돌려준다.
class_name BossPatternLibrary
extends RefCounted

const DEFAULT_PATH := "res://combat/boss_attack_patterns.json"


static func load_json(path: String = DEFAULT_PATH) -> Dictionary:
	var out := {"patterns": {}, "sequence": [], "schema_version": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[PatternLibrary] cannot open %s" % path)
		return out
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[PatternLibrary] bad JSON in %s" % path)
		return out
	out["schema_version"] = String(data.get("schema_version", ""))
	for d in data.get("patterns", []):
		var p := BossAttackPattern.from_dict(d)
		out["patterns"][p.id] = p
	for id in data.get("prototype_sequence", []):
		if out["patterns"].has(id):
			out["sequence"].append(String(id))
		else:
			push_warning("[PatternLibrary] sequence refers to unknown pattern %s" % id)
	return out
