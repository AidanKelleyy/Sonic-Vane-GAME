@tool
extends RefCounted

const WAVEFORM: Script = preload("res://addons/ls5_lipsync/editor/lip_sync_waveform.gd")


static func analyze(stream: AudioStream, start: float, end: float, pause: float) -> Dictionary:
	var duration: float = stream.get_length() if stream else end
	var bins: int = clampi(ceili(duration / 0.005), 2048, 32768)
	var decoded: Dictionary = WAVEFORM.analyze(stream, bins)
	var peaks: PackedFloat32Array = decoded["peaks"]
	var regions: Array[Vector2] = WAVEFORM.speech_regions_from_peaks(peaks, duration, start, end, pause)
	return from_peaks(peaks, duration, regions)


static func from_peaks(peaks: PackedFloat32Array, duration: float, regions: Array[Vector2]) -> Dictionary:
	var result: Dictionary = {"duration": duration, "regions": regions, "energy": PackedFloat32Array(), "nuclei": PackedFloat32Array()}
	if peaks.is_empty() or duration <= 0.0:
		return result
	var stride: float = duration / float(peaks.size())
	var radius: int = maxi(1, roundi(0.012 / stride))
	var sums: PackedFloat64Array = PackedFloat64Array()
	sums.resize(peaks.size() + 1)
	for index: int in range(peaks.size()):
		sums[index + 1] = sums[index] + peaks[index]
	var energy: PackedFloat32Array = PackedFloat32Array()
	energy.resize(peaks.size())
	var maximum: float = 0.0
	for index: int in range(peaks.size()):
		var first: int = maxi(0, index - radius)
		var last: int = mini(peaks.size(), index + radius + 1)
		energy[index] = float(sums[last] - sums[first]) / float(last - first)
		maximum = maxf(maximum, energy[index])
	if maximum <= 0.0001:
		return result
	for index: int in range(energy.size()):
		energy[index] /= maximum
	result["energy"] = energy
	var nuclei: PackedFloat32Array = PackedFloat32Array()
	var neighborhood: int = maxi(2, roundi(0.045 / stride))
	for index: int in range(1, energy.size() - 1):
		if energy[index] < 0.15 or energy[index] < energy[index - 1] or energy[index] <= energy[index + 1]:
			continue
		var left_min: float = energy[index]
		var right_min: float = energy[index]
		for sample: int in range(maxi(0, index - neighborhood), index):
			left_min = minf(left_min, energy[sample])
		for sample: int in range(index + 1, mini(energy.size(), index + neighborhood + 1)):
			right_min = minf(right_min, energy[sample])
		if energy[index] - maxf(left_min, right_min) < 0.08:
			continue
		var time: float = float(index) * stride
		if not nuclei.is_empty() and time - nuclei[-1] < 0.075:
			if energy[index] > energy_at(result, nuclei[-1]):
				nuclei[-1] = time
		else:
			nuclei.append(time)
	result["nuclei"] = nuclei
	return result


static func energy_at(analysis: Dictionary, time: float) -> float:
	var energy: PackedFloat32Array = analysis.get("energy", PackedFloat32Array())
	var duration: float = float(analysis.get("duration", 0.0))
	if energy.is_empty() or duration <= 0.0:
		return 1.0
	var index: int = clampi(floori(time / duration * float(energy.size())), 0, energy.size() - 1)
	return energy[index]


static func nearby_peak(analysis: Dictionary, expected: float, lower: float, upper: float) -> float:
	var selected: float = expected
	var distance: float = INF
	var nuclei: PackedFloat32Array = analysis.get("nuclei", PackedFloat32Array())
	for time: float in nuclei:
		if time < lower or time > upper:
			continue
		var candidate: float = absf(time - expected)
		if candidate < distance:
			distance = candidate
			selected = time
	return selected


static func nearby_valley(analysis: Dictionary, expected: float, lower: float, upper: float) -> float:
	var energy: PackedFloat32Array = analysis.get("energy", PackedFloat32Array())
	var duration: float = float(analysis.get("duration", 0.0))
	if energy.is_empty() or duration <= 0.0 or upper <= lower:
		return expected
	var stride: float = duration / float(energy.size())
	var first: int = clampi(ceili(lower / stride), 0, energy.size() - 1)
	var last: int = clampi(floori(upper / stride), first, energy.size() - 1)
	var minimum: float = 1.0
	var maximum: float = 0.0
	for index: int in range(first, last + 1):
		minimum = minf(minimum, energy[index])
		maximum = maxf(maximum, energy[index])
	if maximum - minimum < 0.12:
		return expected
	var selected: float = expected
	var best: float = INF
	var radius: float = maxf(expected - lower, upper - expected)
	for index: int in range(first, last + 1):
		var time: float = float(index) * stride
		var score: float = (energy[index] - minimum) / (maximum - minimum) + absf(time - expected) / maxf(radius, 0.001) * 0.35
		if score < best:
			best = score
			selected = time
	return selected


static func same_region(analysis: Dictionary, start: float, end: float) -> bool:
	var regions: Array[Vector2] = analysis.get("regions", [])
	for region: Vector2 in regions:
		if start >= region.x - 0.000001 and end <= region.y + 0.000001:
			return true
	return false


static func refine_words(words: Array[Dictionary], analysis: Dictionary) -> void:
	for index: int in range(words.size() - 1):
		var current: Dictionary = words[index]
		var following: Dictionary = words[index + 1]
		var boundary: float = float(current["end"])
		if absf(float(following["start"]) - boundary) > 0.00001:
			continue
		var radius: float = minf(0.09, minf(boundary - float(current["start"]), float(following["end"]) - boundary) * 0.25)
		if not same_region(analysis, boundary - radius, boundary + radius):
			continue
		boundary = nearby_valley(analysis, boundary, boundary - radius, boundary + radius)
		current["end"] = boundary
		following["start"] = boundary


static func refine_cues(cues: Array[LipSyncCue], analysis: Dictionary) -> void:
	for index: int in range(cues.size() - 1):
		var current: LipSyncCue = cues[index]
		var following: LipSyncCue = cues[index + 1]
		var boundary: float = current.end_time
		if absf(following.start_time - boundary) > 0.00001:
			continue
		var radius: float = minf(0.045, minf(boundary - current.start_time, following.end_time - boundary) * 0.25)
		if not same_region(analysis, boundary - radius, boundary + radius):
			continue
		boundary = nearby_valley(analysis, boundary, boundary - radius, boundary + radius)
		current.end_time = boundary
		following.start_time = boundary
