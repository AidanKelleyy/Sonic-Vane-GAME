@tool
extends RefCounted

const ALIGNMENT: Script = preload("res://addons/ls5_lipsync/editor/lip_sync_alignment.gd")

const SPELLINGS: Dictionary = {
	"VIS_AE": ["ae", "ai", "ay", "ei", "ey"],
	"VIS_Ah": ["ah", "a"],
	"VIS_B_M_P": ["b", "m", "p"],
	"VIS_Ch_J": ["tch", "dge", "ch", "sh", "j"],
	"VIS_EE": ["ee", "ea", "ie", "e", "y"],
	"VIS_F_V": ["f", "v", "ph"],
	"VIS_Ih": ["ih", "i"],
	"VIS_K_G_H_NG": ["ng", "ck", "k", "g", "h", "c", "q"],
	"VIS_Oh": ["oa", "oe", "ow", "oh", "aw", "au", "o"],
	"VIS_R": ["r"],
	"VIS_S_Z": ["ss", "s", "z"],
	"VIS_T_L_D_N": ["t", "l", "d", "n"],
	"VIS_Th": ["th"],
	"VIS_Uh": ["uh", "u"],
	"VIS_W_OO": ["oo", "ou", "ue", "ui", "w"],
}

const SHORT_EA_STEMS = ["head", "bread", "dead", "ready", "health", "wealth", "measure", "pleasant", "great", "break", "steak", "bear", "pear", "wear"]
const SHORT_OO_STEMS = ["book", "cook", "look", "good", "wood", "foot", "stood", "hood", "shook", "brook", "hook", "soot"]
const HARD_G_STARTS = ["get", "give", "gift", "girl", "gear", "geese", "gig"]


static func estimate_duration(transcript: String, words_per_minute: float = 165.0) -> float:
	var regex: RegEx = RegEx.new()
	regex.compile("[A-Za-z']+")
	var word_count: int = regex.search_all(transcript).size()
	return float(word_count) * 60.0 / maxf(words_per_minute, 1.0)


static func generate(clip: LipSyncClip) -> void:
	if not clip or not clip.profile or not clip.audio:
		return
	var words: Array[String] = []
	var regex: RegEx = RegEx.new()
	regex.compile("[A-Za-z']+")
	for result: RegExMatch in regex.search_all(clip.transcript):
		words.append(result.get_string())
	if words.is_empty():
		return
	var start_time: float = clampf(clip.audible_start, 0.0, clip.audio.get_length())
	var end_time: float = clip.audible_end if clip.audible_end > start_time else clip.audio.get_length()
	end_time = clampf(end_time, start_time, clip.audio.get_length())
	if end_time <= start_time:
		return
	var analysis: Dictionary = ALIGNMENT.analyze(clip.audio, start_time, end_time, clip.generation_pause_threshold)
	var regions: Array[Vector2] = analysis["regions"]
	var word_units: Array[Array] = []
	var total_weight: float = 0.0
	var unit_count: int = 0
	for word: String in words:
		var units: Array[Dictionary] = _word_units(word.to_lower(), clip.profile)
		word_units.append(units)
		unit_count += units.size()
		for unit: Dictionary in units:
			total_weight += float(unit["weight"])
	if total_weight <= 0.0:
		return
	var words_generated: Array[Dictionary] = []
	var available_time: float = _regions_duration(regions)
	var gap_count: int = maxi(0, unit_count - 1)
	var minimum_cue_time: float = 0.02
	var maximum_padding: float = maxf(0.0, (available_time - float(unit_count) * minimum_cue_time) / float(gap_count)) if gap_count > 0 else 0.0
	var padding: float = minf(maxf(0.0, snappedf(clip.generation_padding, 0.01)), maximum_padding)
	var seconds_per_weight: float = maxf(0.0, available_time - padding * float(gap_count)) / total_weight
	var cursor: float = 0.0
	var cue_index: int = 0
	for word_index: int in range(words.size()):
		var word_start: float = cursor
		var word_end: float = cursor
		for unit: Dictionary in word_units[word_index]:
			cursor += float(unit["weight"]) * seconds_per_weight
			word_end = cursor
			cue_index += 1
			if cue_index < unit_count:
				cursor += padding
		words_generated.append({"word": words[word_index], "start": word_start, "end": word_end})
	for span: Dictionary in words_generated:
		span["start"] = _region_time(float(span["start"]), regions, true)
		span["end"] = _region_time(float(span["end"]), regions, false)
	ALIGNMENT.refine_words(words_generated, analysis)
	var previous_words: Array[Dictionary] = clip.word_spans
	clip.word_spans = words_generated
	if not regenerate_from_words(clip, analysis):
		clip.word_spans = previous_words


## Rebuilds visemes inside word guidance, reusing decoded audio when supplied.
static func regenerate_from_words(clip: LipSyncClip, analysis: Dictionary = {}) -> bool:
	if not clip or not clip.profile or clip.word_spans.is_empty():
		return false
	var units_by_word: Array[Array] = []
	var previous_end: float = 0.0
	for span: Dictionary in clip.word_spans:
		var word: String = String(span.get("word", ""))
		var start: float = float(span.get("start", 0.0))
		var end: float = float(span.get("end", 0.0))
		if word.strip_edges().is_empty() or end <= start or start < previous_end:
			return false
		units_by_word.append(_word_units(word.to_lower(), clip.profile))
		previous_end = end
	var range_end: float = maxf(previous_end, clip.audio.get_length() if clip.audio else previous_end)
	if analysis.is_empty():
		analysis = ALIGNMENT.analyze(clip.audio, 0.0, range_end, clip.generation_pause_threshold)
	var regions: Array[Vector2] = analysis["regions"]
	var regenerated: Array[LipSyncCue] = []
	var padding: float = maxf(0.0, snappedf(clip.generation_padding, 0.01))
	for word_index: int in range(clip.word_spans.size()):
		var span: Dictionary = clip.word_spans[word_index]
		var start: float = float(span["start"])
		var end: float = float(span["end"])
		var left_trim: float = 0.0
		var right_trim: float = 0.0
		if word_index > 0:
			var previous_word_end: float = float(clip.word_spans[word_index - 1]["end"])
			left_trim = maxf(0.0, padding - maxf(0.0, start - previous_word_end)) * 0.5
		if word_index + 1 < clip.word_spans.size():
			var next_start: float = float(clip.word_spans[word_index + 1]["start"])
			right_trim = maxf(0.0, padding - maxf(0.0, next_start - end)) * 0.5
		var units: Array[Dictionary] = units_by_word[word_index]
		var minimum_cue_time: float = 0.02
		var trim_limit: float = maxf(0.0, end - start - float(units.size()) * minimum_cue_time)
		if left_trim + right_trim > trim_limit and left_trim + right_trim > 0.0:
			var trim_scale: float = trim_limit / (left_trim + right_trim)
			left_trim *= trim_scale
			right_trim *= trim_scale
		start += left_trim
		end -= right_trim
		var word_regions: Array[Vector2] = _regions_in_span(regions, start, end)
		var word_duration: float = _regions_duration(word_regions)
		if word_duration <= 0.0:
			return false
		var gap_count: int = maxi(0, units.size() - 1)
		var maximum_gap: float = maxf(0.0, (word_duration - float(units.size()) * minimum_cue_time) / float(gap_count)) if gap_count > 0 else 0.0
		var local_padding: float = minf(padding, maximum_gap)
		var weight_total: float = 0.0
		for unit: Dictionary in units:
			weight_total += float(unit["weight"])
		var seconds_per_weight: float = maxf(0.0, word_duration - local_padding * float(gap_count)) / maxf(weight_total, 0.001)
		var cursor: float = 0.0
		var word_cues: Array[LipSyncCue] = []
		for unit_index: int in range(units.size()):
			var unit: Dictionary = units[unit_index]
			var cue: LipSyncCue = LipSyncCue.new()
			cue.pose_id = unit["id"]
			cue.speech_role = int(unit["role"])
			cue.start_time = cursor
			cursor += float(unit["weight"]) * seconds_per_weight
			cue.end_time = cursor
			word_cues.append(cue)
			if unit_index + 1 < units.size():
				cursor += local_padding
		var expanded: Array[LipSyncCue] = _expand_cues(word_cues, word_regions)
		ALIGNMENT.refine_cues(expanded, analysis)
		regenerated.append_array(_prepare_word_cues(expanded, clip, analysis))
	if regenerated.is_empty():
		return false
	clip.viseme_cues = regenerated
	_add_repeat_releases(clip, analysis)
	_shape_generated_cues(clip, regions, analysis)
	clip.emit_changed()
	return true


static func _regions_duration(regions: Array[Vector2]) -> float:
	var duration: float = 0.0
	for region: Vector2 in regions:
		duration += region.y - region.x
	return duration


static func _region_time(time: float, regions: Array[Vector2], following_edge: bool) -> float:
	for region: Vector2 in regions:
		var duration: float = region.y - region.x
		if time < duration - 0.000001 or (not following_edge and time <= duration + 0.000001):
			return region.x + clampf(time, 0.0, duration)
		time -= duration
	return regions[-1].y if not regions.is_empty() else 0.0


static func _regions_in_span(regions: Array[Vector2], start: float, end: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for region: Vector2 in regions:
		var intersection: Vector2 = Vector2(maxf(start, region.x), minf(end, region.y))
		if intersection.y > intersection.x:
			result.append(intersection)
	return result


static func _expand_cues(cues: Array[LipSyncCue], regions: Array[Vector2]) -> Array[LipSyncCue]:
	var result: Array[LipSyncCue] = []
	for cue: LipSyncCue in cues:
		var offset: float = 0.0
		for region: Vector2 in regions:
			var duration: float = region.y - region.x
			var start: float = maxf(cue.start_time, offset)
			var end: float = minf(cue.end_time, offset + duration)
			if end > start + 0.000001:
				var segment: LipSyncCue = cue.duplicate() as LipSyncCue
				segment.start_time = region.x + start - offset
				segment.end_time = region.x + end - offset
				result.append(segment)
			offset += duration
	return result


static func _speech_role(clip: LipSyncClip, cue: LipSyncCue) -> int:
	if cue.speech_role != LipSyncPose.SpeechRole.AUTOMATIC:
		return cue.speech_role
	var pose: LipSyncPose = clip.profile.find_pose(cue.pose_id)
	return pose.get_speech_role() if pose else LipSyncPose.SpeechRole.REST


static func _vowel_role(role: int) -> bool:
	return role in [LipSyncPose.SpeechRole.VOWEL, LipSyncPose.SpeechRole.ROUNDED_VOWEL]


static func _prepare_word_cues(cues: Array[LipSyncCue], clip: LipSyncClip, analysis: Dictionary) -> Array[LipSyncCue]:
	var merged: Array[LipSyncCue] = []
	for cue: LipSyncCue in cues:
		var role: int = _speech_role(clip, cue)
		if not merged.is_empty() and _vowel_role(role):
			var previous: LipSyncCue = merged[-1]
			if previous.pose_id == cue.pose_id and previous.speech_role == cue.speech_role and absf(previous.end_time - cue.start_time) < 0.000001:
				previous.end_time = cue.end_time
				continue
		merged.append(cue)
	var result: Array[LipSyncCue] = []
	for cue: LipSyncCue in merged:
		var role: int = _speech_role(clip, cue)
		var pose: LipSyncPose = clip.profile.find_pose(cue.pose_id)
		var strength_scale: float = pose.generation_strength if pose else 1.0
		var duration: float = cue.end_time - cue.start_time
		if role == LipSyncPose.SpeechRole.CONSONANT:
			cue.strength = 0.85
		elif role == LipSyncPose.SpeechRole.FRICATIVE:
			cue.strength = 0.9
		cue.strength *= strength_scale
		if not _vowel_role(role) and role not in [LipSyncPose.SpeechRole.SUSTAINED_CLOSURE, LipSyncPose.SpeechRole.FRICATIVE]:
			result.append(cue)
			continue
		if duration < 0.24:
			result.append(cue)
			continue
		var count: int = clampi(ceili(duration / 0.14), 2, 32)
		var levels: Array[float] = []
		var maximum: float = 0.0
		var minimum: float = 1.0
		for index: int in range(count):
			var time: float = cue.start_time + duration * (float(index) + 0.5) / float(count)
			var level: float = ALIGNMENT.energy_at(analysis, time)
			levels.append(level)
			maximum = maxf(maximum, level)
			minimum = minf(minimum, level)
		for index: int in range(count):
			var segment: LipSyncCue = cue.duplicate() as LipSyncCue
			segment.start_time = cue.start_time + duration * float(index) / float(count)
			segment.end_time = cue.start_time + duration * float(index + 1) / float(count)
			var emphasis: float = levels[index] / maxf(maximum, 0.001)
			segment.strength = lerpf(0.78, 1.0, sqrt(emphasis)) if maximum - minimum >= 0.12 else (1.0 if index == 0 else 0.92)
			if role == LipSyncPose.SpeechRole.SUSTAINED_CLOSURE:
				segment.strength = 1.0
			elif role == LipSyncPose.SpeechRole.FRICATIVE:
				segment.strength *= 0.9
			segment.strength *= strength_scale
			result.append(segment)
	return result


static func _add_repeat_releases(clip: LipSyncClip, analysis: Dictionary) -> void:
	if clip.generation_padding > 0.0:
		return
	var releases: Array[LipSyncCue] = []
	for index: int in range(clip.word_spans.size() - 1):
		var word_end: float = float(clip.word_spans[index]["end"])
		var next_start: float = float(clip.word_spans[index + 1]["start"])
		if next_start - word_end >= clip.generation_pause_threshold or not ALIGNMENT.same_region(analysis, word_end, next_start):
			continue
		var before: LipSyncCue
		var after: LipSyncCue
		for cue: LipSyncCue in clip.viseme_cues:
			if cue.end_time <= word_end + 0.000001:
				before = cue
			if not after and cue.start_time >= next_start - 0.000001:
				after = cue
		if not before or not after or before.pose_id != after.pose_id or not _vowel_role(_speech_role(clip, before)):
			continue
		var half_width: float = minf(0.025, minf(before.end_time - before.start_time, after.end_time - after.start_time) * 0.2)
		var boundary: float = (word_end + next_start) * 0.5
		var release: LipSyncCue = LipSyncCue.new()
		release.pose_id = before.pose_id
		release.speech_role = before.speech_role
		release.start_time = boundary - half_width
		release.end_time = boundary + half_width
		release.strength = minf(before.strength, after.strength) * 0.78
		before.end_time = minf(before.end_time, release.start_time)
		after.start_time = maxf(after.start_time, release.end_time)
		releases.append(release)
	clip.viseme_cues.append_array(releases)


static func _shape_generated_cues(clip: LipSyncClip, regions: Array[Vector2], analysis: Dictionary = {}) -> void:
	var cues: Array[LipSyncCue] = clip.viseme_cues
	cues.sort_custom(func(a: LipSyncCue, b: LipSyncCue) -> bool: return a.start_time < b.start_time)
	var starts: Array[float] = []
	var ends: Array[float] = []
	var arrivals: Array[float] = []
	var departures: Array[float] = []
	for index: int in range(cues.size()):
		var cue: LipSyncCue = cues[index]
		var duration: float = maxf(0.0, cue.end_time - cue.start_time)
		var hold: float = minf(maxf(0.0, clip.generation_max_hold), duration * (1.0 - clampf(clip.generation_transition_amount, 0.0, 1.0)))
		var arrival: float = cue.start_time + minf(0.08, (duration - hold) * 0.4)
		var role: int = _speech_role(clip, cue)
		if role in [LipSyncPose.SpeechRole.CLOSURE, LipSyncPose.SpeechRole.SUSTAINED_CLOSURE]:
			hold = minf(maxf(0.0, clip.generation_max_hold), maxf(hold, minf(0.035, duration * 0.4)))
			arrival = cue.start_time + minf(0.025, (duration - hold) * 0.4)
		elif role == LipSyncPose.SpeechRole.CONSONANT:
			hold = minf(hold, minf(0.012, duration * 0.08))
			arrival = cue.start_time + minf(0.035, (duration - hold) * 0.3)
		elif role == LipSyncPose.SpeechRole.FRICATIVE:
			arrival = cue.start_time + minf(0.045, (duration - hold) * 0.35)
		elif role == LipSyncPose.SpeechRole.ROUNDED_VOWEL:
			arrival = cue.start_time + minf(0.06, (duration - hold) * 0.3)
		var pose: LipSyncPose = clip.profile.find_pose(cue.pose_id)
		if pose:
			hold = minf(maxf(0.0, clip.generation_max_hold), minf(duration, hold * pose.generation_hold_scale))
			arrival = cue.start_time + (arrival - cue.start_time) * pose.generation_attack_scale
		arrival = clampf(arrival, cue.start_time, cue.end_time - hold)
		if _vowel_role(role):
			arrival = ALIGNMENT.nearby_peak(analysis, arrival, maxf(cue.start_time + duration * 0.15, arrival - 0.07), minf(cue.end_time - hold - duration * 0.1, arrival + 0.07))
		starts.append(cue.start_time)
		ends.append(cue.end_time)
		arrivals.append(arrival)
		departures.append(arrival + hold)
		cue.row = index % LipSyncCue.ROW_COUNT
		cue.asymmetric_blends = true
		cue.blend_in = arrival - cue.start_time
		cue.blend_out = cue.end_time - arrival - hold
	for index: int in range(cues.size() - 1):
		var current: LipSyncCue = cues[index]
		var following: LipSyncCue = cues[index + 1]
		var gap: float = starts[index + 1] - ends[index]
		if gap >= clip.generation_pause_threshold or (clip.generation_padding > 0.0 and gap > 0.000001):
			continue
		var same_region: bool = false
		for region: Vector2 in regions:
			if ends[index] >= region.x - 0.000001 and ends[index] <= region.y + 0.000001 and starts[index + 1] >= region.x - 0.000001 and starts[index + 1] <= region.y + 0.000001:
				same_region = true
				break
		if not same_region:
			continue
		var overlap: float = arrivals[index + 1] - departures[index]
		if overlap <= 0.0:
			continue
		current.end_time = arrivals[index + 1]
		following.start_time = departures[index]
		current.blend_out = overlap
		following.blend_in = overlap


static func _word_units(word: String, profile: LipSyncProfile) -> Array[Dictionary]:
	var custom_patterns: Array[Dictionary] = []
	var default_patterns: Array[Dictionary] = []
	for pose: LipSyncPose in profile.visemes:
		if not pose or pose.id == profile.silent_viseme_id:
			continue
		var spellings: PackedStringArray = pose.spelling_patterns
		var patterns: Array[Dictionary] = custom_patterns
		if spellings.is_empty():
			spellings = PackedStringArray(SPELLINGS.get(String(pose.id), []))
			patterns = default_patterns
		for spelling: String in spellings:
			if not spelling.is_empty():
				patterns.append({"text": spelling.to_lower(), "id": pose.id})
	custom_patterns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["text"]).length() > String(b["text"]).length())
	default_patterns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["text"]).length() > String(b["text"]).length())
	var units: Array[Dictionary] = []
	var index: int = 0
	while index < word.length():
		var letter: String = word.substr(index, 1)
		if letter == "'":
			index += 1
			continue
		var custom_match: Dictionary = _match_spelling(word, index, custom_patterns)
		if not custom_match.is_empty():
			_append_unit(units, custom_match["id"], String(custom_match["text"]))
			index += String(custom_match["text"]).length()
			continue
		if (index == 0 and word.substr(0, 2) in ["kn", "wr"]) or (letter == "b" and index > 0 and index == word.length() - 1 and word.substr(index - 1, 1) == "m"):
			index += 1
			continue
		if letter == "u" and (word.begins_with("guy") or word.begins_with("buy")):
			index += 1
			continue
		if index > 0 and letter == word.substr(index - 1, 1) and not _is_vowel(letter):
			index += 1
			continue
		if word.substr(index, 2) == "qu":
			_append_available_unit(units, profile, &"VIS_K_G_H_NG", "q")
			_append_available_unit(units, profile, &"VIS_W_OO", "w")
			index += 2
			continue
		if letter == "x":
			if index > 0:
				_append_available_unit(units, profile, &"VIS_K_G_H_NG", "k")
			_append_available_unit(units, profile, &"VIS_S_Z", "s")
			index += 1
			continue
		if word.substr(index, 2) == "gh":
			if index == 0:
				_append_available_unit(units, profile, &"VIS_K_G_H_NG", "g")
			elif _has_stem(word, ["laugh", "cough", "tough", "rough", "enough"]):
				_append_available_unit(units, profile, &"VIS_F_V", "f")
			index += 2
			continue
		var match_result: Dictionary = _match_spelling(word, index, default_patterns)
		if match_result.is_empty():
			index += 1
			continue
		var spelling: String = String(match_result["text"])
		var pose_id: StringName = _context_pose(word, index, spelling, match_result["id"], profile)
		if pose_id != &"":
			_append_unit(units, pose_id, spelling)
		index += spelling.length()
	if units.is_empty():
		units.append({"id": profile.silent_viseme_id, "weight": 1.0})
	for unit: Dictionary in units:
		var pose: LipSyncPose = profile.find_pose(unit["id"])
		unit["role"] = LipSyncPose.SpeechRole.REST
		if not pose:
			continue
		var role: int = pose.get_speech_role()
		var spelling: String = String(unit.get("spelling", ""))
		if pose.speech_role == LipSyncPose.SpeechRole.AUTOMATIC:
			if pose.id == &"VIS_B_M_P" and spelling == "m":
				role = LipSyncPose.SpeechRole.SUSTAINED_CLOSURE
			elif pose.id == &"VIS_W_OO" and spelling == "w":
				role = LipSyncPose.SpeechRole.CONSONANT
			elif pose.id == &"VIS_Ch_J" and spelling == "sh":
				role = LipSyncPose.SpeechRole.FRICATIVE
		unit["role"] = role
		match role:
			LipSyncPose.SpeechRole.VOWEL:
				unit["weight"] = 1.3
			LipSyncPose.SpeechRole.ROUNDED_VOWEL:
				unit["weight"] = 1.35
			LipSyncPose.SpeechRole.CLOSURE:
				unit["weight"] = 0.65
			LipSyncPose.SpeechRole.SUSTAINED_CLOSURE:
				unit["weight"] = 0.95
			LipSyncPose.SpeechRole.FRICATIVE:
				unit["weight"] = 0.9
			LipSyncPose.SpeechRole.CONSONANT:
				unit["weight"] = 0.8
		unit["weight"] = float(unit["weight"]) * pose.generation_duration_scale
	return units


static func _match_spelling(word: String, index: int, patterns: Array[Dictionary]) -> Dictionary:
	for pattern: Dictionary in patterns:
		var spelling: String = String(pattern["text"])
		if word.substr(index, spelling.length()) == spelling:
			return pattern
	return {}


static func _append_available_unit(units: Array[Dictionary], profile: LipSyncProfile, pose_id: StringName, spelling: String) -> void:
	if profile.find_pose(pose_id):
		_append_unit(units, pose_id, spelling)


static func _append_unit(units: Array[Dictionary], pose_id: StringName, spelling: String) -> void:
	var vowel_pose: bool = pose_id in [&"VIS_AE", &"VIS_Ah", &"VIS_EE", &"VIS_Ih", &"VIS_Oh", &"VIS_Uh"]
	var vowel_spelling: bool = not spelling.is_empty() and _is_vowel(spelling.substr(0, 1))
	units.append({"id": pose_id, "spelling": spelling, "weight": 1.3 if vowel_pose or vowel_spelling else 0.8})


static func _context_pose(word: String, index: int, spelling: String, fallback: StringName, profile: LipSyncProfile) -> StringName:
	var next_letter: String = word.substr(index + spelling.length(), 1)
	match spelling:
		"e":
			if index == word.length() - 1:
				if word == "the":
					return _available_pose(profile, &"VIS_Uh", fallback)
				return _available_pose(profile, &"VIS_EE", fallback) if word in ["be", "he", "me", "she", "we"] else &""
			if next_letter == "r":
				return _available_pose(profile, &"VIS_Uh", fallback)
			return _available_pose(profile, &"VIS_EE", fallback) if _has_magic_e(word, index) else _available_pose(profile, &"VIS_AE", fallback)
		"ea":
			return _available_pose(profile, &"VIS_AE", fallback) if _has_stem(word, SHORT_EA_STEMS) else fallback
		"ei":
			return _available_pose(profile, &"VIS_EE", fallback) if _has_stem(word, ["ceiv", "ceil", "seiz", "weird"]) else fallback
		"ey":
			return _available_pose(profile, &"VIS_EE", fallback) if _has_stem(word, ["key", "money", "honey", "monkey"]) else fallback
		"ie":
			return _available_pose(profile, &"VIS_AE", fallback) if word.ends_with("ie") and word.length() <= 4 else fallback
		"a":
			return _available_pose(profile, &"VIS_Ah", fallback) if next_letter == "r" else _available_pose(profile, &"VIS_AE", fallback)
		"i":
			if next_letter == "r":
				return _available_pose(profile, &"VIS_Uh", fallback)
			return _available_pose(profile, &"VIS_AE", fallback) if word == "i" or _has_magic_e(word, index) else fallback
		"o":
			if _has_magic_e(word, index) or index == word.length() - 1:
				return fallback
			return _available_pose(profile, &"VIS_Ah", fallback) if not next_letter.is_empty() and not _is_vowel(next_letter) and index + 2 >= word.length() else fallback
		"u":
			if _has_magic_e(word, index):
				return _available_pose(profile, &"VIS_W_OO", fallback)
			if next_letter == "r":
				return fallback
			return fallback if _has_stem(word, ["put", "push", "pull", "bush", "full"]) else _available_pose(profile, &"VIS_Ah", fallback)
		"y":
			return _available_pose(profile, &"VIS_AE", fallback) if word in ["my", "by", "why", "try", "fly", "sky", "cry", "dry", "shy", "reply"] or word.begins_with("guy") or word.begins_with("buy") else fallback
		"c":
			return _available_pose(profile, &"VIS_S_Z", fallback) if next_letter in ["e", "i", "y"] else fallback
		"g":
			return _available_pose(profile, &"VIS_Ch_J", fallback) if next_letter in ["e", "i", "y"] and not _has_stem(word, HARD_G_STARTS) else fallback
		"oo":
			return _available_pose(profile, &"VIS_Uh", fallback) if _has_stem(word, SHORT_OO_STEMS) else fallback
		"ou":
			if _has_stem(word, ["would", "could", "should", "touch", "young", "country"]):
				return _available_pose(profile, &"VIS_Uh", fallback)
			return _available_pose(profile, &"VIS_AE", fallback) if _has_stem(word, ["out", "ouse", "oud", "oun"]) else fallback
		"ow":
			return _available_pose(profile, &"VIS_AE", fallback) if _has_stem(word, ["cow", "how", "now", "wow", "down", "town", "brown", "flower", "power", "shower"]) else fallback
	return fallback


static func _available_pose(profile: LipSyncProfile, preferred: StringName, fallback: StringName) -> StringName:
	return preferred if profile.find_pose(preferred) else fallback


static func _has_magic_e(word: String, index: int) -> bool:
	if word in ["have", "give", "love", "some", "one", "done"]:
		return false
	return index == word.length() - 3 and word.ends_with("e") and not _is_vowel(word.substr(index + 1, 1))


static func _has_stem(word: String, stems: Array) -> bool:
	for stem: String in stems:
		if word.contains(stem):
			return true
	return false


static func _is_vowel(letter: String) -> bool:
	return letter in ["a", "e", "i", "o", "u"]

