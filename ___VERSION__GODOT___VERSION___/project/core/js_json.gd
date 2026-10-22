class_name JsJson
extends RefCounted
## JSON text the way JavaScript produces it: JSON.stringify (compact or indented) with the shortest round-trip number
## digits of Number::toString, JS key order (integer-like keys first, ascending) and JS string escaping. Needed so a
## save checksum computed over stringify(data) matches the JS game's, in both directions.
## Number printing is Burger & Dybvig's free-format shortest digit generation on a small bignum (Godot's own float
## printing keeps 14 digits and is not round-trip).

const LIMB_BITS := 30
const LIMB_BASE := 1 << LIMB_BITS
const LIMB_MASK := LIMB_BASE - 1


# ---------------------------------------------------------------- bignum (little-endian base 2^30 limbs)

static func _big_from_int(v: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	if v == 0:
		out.append(0)
		return out
	while v > 0:
		out.append(v & LIMB_MASK)
		v >>= LIMB_BITS
	return out


static func _trim(a: PackedInt64Array) -> PackedInt64Array:
	while a.size() > 1 and a[a.size() - 1] == 0:
		a.remove_at(a.size() - 1)
	return a


static func _mul_small(a: PackedInt64Array, k: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var carry := 0
	for limb in a:
		var cur: int = limb * k + carry
		out.append(cur & LIMB_MASK)
		carry = cur >> LIMB_BITS
	while carry > 0:
		out.append(carry & LIMB_MASK)
		carry >>= LIMB_BITS
	return _trim(out)


static func _shl(a: PackedInt64Array, bits: int) -> PackedInt64Array:
	var limbs: int = bits / LIMB_BITS
	var rem: int = bits % LIMB_BITS
	var out := PackedInt64Array()
	for i in limbs:
		out.append(0)
	var carry := 0
	for limb in a:
		var cur: int = (limb << rem) | carry
		out.append(cur & LIMB_MASK)
		carry = cur >> LIMB_BITS
	if carry > 0:
		out.append(carry)
	return _trim(out)


static func _cmp(a: PackedInt64Array, b: PackedInt64Array) -> int:
	if a.size() != b.size():
		return 1 if a.size() > b.size() else -1
	var i: int = a.size() - 1
	while i >= 0:
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
		i -= 1
	return 0


static func _add(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	var carry := 0
	for i in maxi(a.size(), b.size()):
		var cur: int = (a[i] if i < a.size() else 0) + (b[i] if i < b.size() else 0) + carry
		out.append(cur & LIMB_MASK)
		carry = cur >> LIMB_BITS
	if carry > 0:
		out.append(carry)
	return _trim(out)


## a - b, requires a >= b.
static func _sub(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	var borrow := 0
	for i in a.size():
		var cur: int = a[i] - (b[i] if i < b.size() else 0) - borrow
		if cur < 0:
			cur += LIMB_BASE
			borrow = 1
		else:
			borrow = 0
		out.append(cur)
	return _trim(out)


static func _pow10(n: int) -> PackedInt64Array:
	var r := _big_from_int(1)
	for i in n:
		r = _mul_small(r, 10)
	return r


# ---------------------------------------------------------------- Number::toString

## JS String(x) for a finite double (shortest digits that round-trip).
static func num_to_string(x: float) -> String:
	if is_nan(x):
		return "NaN"
	if is_inf(x):
		return "Infinity" if x > 0.0 else "-Infinity"
	if x == 0.0:
		return "0"
	var neg := x < 0.0
	var v: float = absf(x)
	if v < 9007199254740992.0 and v == floor(v):
		return ("-" if neg else "") + str(int(v))
	var bits: int = _double_bits(v)
	var frac: int = bits & 0xFFFFFFFFFFFFF
	var bexp: int = (bits >> 52) & 0x7FF
	var f: int
	var e: int
	if bexp == 0:
		f = frac
		e = -1074
	else:
		f = frac | (1 << 52)
		e = bexp - 1075
	var digits := _shortest_digits(f, e, bexp == 0 or frac != 0 or bexp == 1)
	var d: String = digits[0]
	var k: int = digits[1]  # value = 0.d * 10^k
	var s := _layout(d, k)
	return ("-" if neg else "") + s


static func _double_bits(v: float) -> int:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return b.decode_s64(0)


## Burger & Dybvig free-format: returns [digit string, k] with value ~ 0.d1d2.. x 10^k.
static func _shortest_digits(f: int, e: int, not_boundary_hint: bool) -> Array:
	var even: bool = (f & 1) == 0
	var min_e := -1074
	var hidden: int = 1 << 52
	var r: PackedInt64Array
	var s: PackedInt64Array
	var mp: PackedInt64Array
	var mm: PackedInt64Array
	if e >= 0:
		var be: PackedInt64Array = _shl(_big_from_int(1), e)
		if f != hidden:
			r = _mul_small(_shl(_big_from_int(f), e), 2)
			s = _big_from_int(2)
			mp = be
			mm = be
		else:
			r = _mul_small(_shl(_big_from_int(f), e), 4)
			s = _big_from_int(4)
			mp = _mul_small(be, 2)
			mm = be
	else:
		if e == min_e or f != hidden:
			r = _mul_small(_big_from_int(f), 2)
			s = _shl(_big_from_int(1), -e + 1)
			mp = _big_from_int(1)
			mm = _big_from_int(1)
		else:
			r = _mul_small(_big_from_int(f), 4)
			s = _shl(_big_from_int(1), -e + 2)
			mp = _big_from_int(2)
			mm = _big_from_int(1)
	# estimate k = ceil(log10(v))
	var v_approx: float = float(f) * pow(2.0, float(e))
	var k: int = int(ceil(log(v_approx) / log(10.0) - 1e-10)) if v_approx > 0.0 and is_finite(v_approx) else 0
	if v_approx == 0.0 or not is_finite(v_approx):
		# denormal range pow underflow: use exponent arithmetic
		k = int(ceil((float(e) + log(float(f)) / log(2.0)) * 0.30102999566398114 - 1e-10))
	if k >= 0:
		s = _mul_small_pow10(s, k)
	else:
		var scale := _pow10(-k)
		r = _mul_big(r, scale)
		mp = _mul_big(mp, scale)
		mm = _mul_big(mm, scale)
	# fixup: ensure (r + m+) < s (or <= when even), else k + 1
	var hi: PackedInt64Array = _add(r, mp)
	var c: int = _cmp(hi, s)
	if c > 0 or (c == 0 and even):
		s = _mul_small(s, 10)
		k += 1
	else:
		# the estimate may be one too high: multiply up while (r + m+) * 10 < s
		var hi10: PackedInt64Array = _mul_small(hi, 10)
		var c10: int = _cmp(hi10, s)
		while c10 < 0 or (c10 == 0 and not even):
			r = _mul_small(r, 10)
			mp = _mul_small(mp, 10)
			mm = _mul_small(mm, 10)
			k -= 1
			hi10 = _mul_small(_add(r, mp), 10)
			c10 = _cmp(hi10, s)
	var out := ""
	while true:
		r = _mul_small(r, 10)
		mp = _mul_small(mp, 10)
		mm = _mul_small(mm, 10)
		# digit = floor(r / s), r = r mod s, by repeated subtraction (digit < 10)
		var digit := 0
		while _cmp(r, s) >= 0:
			r = _sub(r, s)
			digit += 1
		var c1: int = _cmp(r, mm)
		var tc1: bool = c1 < 0 or (c1 == 0 and even)
		var c2: int = _cmp(_add(r, mp), s)
		var tc2: bool = c2 > 0 or (c2 == 0 and even)
		if not tc1 and not tc2:
			out += str(digit)
			continue
		if tc1 and not tc2:
			out += str(digit)
		elif not tc1 and tc2:
			out += str(digit + 1)
		else:
			# both candidates round-trip: pick the nearer; an exact halfway case rounds to the even digit (V8 bignum-dtoa)
			var cmp_half: int = _cmp(_mul_small(r, 2), s)
			if cmp_half < 0:
				out += str(digit)
			elif cmp_half > 0:
				out += str(digit + 1)
			else:
				out += str(digit if digit % 2 == 0 else digit + 1)
		break
	return [out, k]


static func _mul_small_pow10(a: PackedInt64Array, n: int) -> PackedInt64Array:
	var r := a
	for i in n:
		r = _mul_small(r, 10)
	return r


static func _mul_big(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(a.size() + b.size())
	for i in a.size():
		var carry := 0
		for j in b.size():
			var cur: int = out[i + j] + a[i] * b[j] + carry
			out[i + j] = cur & LIMB_MASK
			carry = cur >> LIMB_BITS
		var idx: int = i + b.size()
		while carry > 0:
			var cur2: int = out[idx] + carry
			out[idx] = cur2 & LIMB_MASK
			carry = cur2 >> LIMB_BITS
			idx += 1
	return _trim(out)


## Number::toString layout of digits d (n digits) with value 0.d x 10^k.
static func _layout(d: String, k: int) -> String:
	var n: int = d.length()
	if n <= k and k <= 21:
		return d + "0".repeat(k - n)
	if 0 < k and k <= 21:
		return d.substr(0, k) + "." + d.substr(k)
	if -6 < k and k <= 0:
		return "0." + "0".repeat(-k) + d
	var exp_v: int = k - 1
	var sign := "+" if exp_v >= 0 else "-"
	var es: String = str(absi(exp_v))
	if n == 1:
		return d + "e" + sign + es
	return d.substr(0, 1) + "." + d.substr(1) + "e" + sign + es


# ---------------------------------------------------------------- JSON.stringify

static func _escape(s: String) -> String:
	var out := "\""
	for i in s.length():
		var cp: int = s.unicode_at(i)
		match cp:
			34: out += "\\\""
			92: out += "\\\\"
			8: out += "\\b"
			12: out += "\\f"
			10: out += "\\n"
			13: out += "\\r"
			9: out += "\\t"
			_:
				if cp < 0x20:
					out += "\\u%04x" % cp
				elif cp >= 0xD800 and cp <= 0xDFFF:
					out += "\\u%04x" % cp
				else:
					out += char(cp)
	return out + "\""


static func _is_index_key(k: String) -> bool:
	if k == "0":
		return true
	if k.length() == 0 or k.length() > 10 or k[0] == "0":
		return false
	for i in k.length():
		var c: int = k.unicode_at(i)
		if c < 48 or c > 57:
			return false
	return int(k) < 4294967295


static func _ordered_keys(d: Dictionary) -> Array:
	var idx: Array = []
	var rest: Array = []
	for k in d.keys():
		var ks := str(k)
		if _is_index_key(ks):
			idx.append(ks)
		else:
			rest.append(ks)
	idx.sort_custom(func(a, b): return int(a) < int(b))
	return idx + rest


## JSON.stringify(value, null, indent). Dictionary values keep insertion order, integer-like keys sort first.
## Returns "" for values JSON cannot hold (undefined-like); NaN/Infinity print as null as in JS.
static func stringify(value: Variant, indent: int = 0) -> String:
	return _write(value, indent, 0)


static func _write(v: Variant, indent: int, depth: int) -> String:
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is int:
		return str(v)
	if v is float:
		return num_to_string(v) if is_finite(v) else "null"
	if v is String or v is StringName:
		return _escape(str(v))
	if v is Array or v is PackedStringArray or v is PackedFloat64Array or v is PackedInt32Array or v is PackedInt64Array or v is PackedFloat32Array:
		var arr: Array = v if v is Array else Array(v)
		if arr.is_empty():
			return "[]"
		var parts: PackedStringArray = []
		for item in arr:
			parts.append(_write(item, indent, depth + 1))
		if indent <= 0:
			return "[" + ",".join(parts) + "]"
		var pad := " ".repeat(indent * (depth + 1))
		return "[\n" + pad + (",\n" + pad).join(parts) + "\n" + " ".repeat(indent * depth) + "]"
	if v is Dictionary:
		var keys := _ordered_keys(v)
		var parts2: PackedStringArray = []
		for k in keys:
			var val: Variant = v[k] if v.has(k) else v[int(k)] if v.has(int(k)) else null
			parts2.append(_escape(k) + (":" if indent <= 0 else ": ") + _write(val, indent, depth + 1))
		if parts2.is_empty():
			return "{}"
		if indent <= 0:
			return "{" + ",".join(parts2) + "}"
		var pad2 := " ".repeat(indent * (depth + 1))
		return "{\n" + pad2 + (",\n" + pad2).join(parts2) + "\n" + " ".repeat(indent * depth) + "}"
	return "null"
