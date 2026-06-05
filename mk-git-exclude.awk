function die(message) {
	print "mk-git-exclude.awk: " FILENAME ":" FNR ": " message >"/fd/2"
	errors = 1
}

function has_slash(s) {
	return index(s, "/") != 0
}

function escape_literal(c) {
	if(c == "." || c == "+" || c == "(" || c == ")" || c == "|" ||
	    c == "^" || c == "$")
		return "\\" c
	return c
}

function translate_class(s, i,    j, c, cls) {
	cls = "["
	i++
	if(i > length(s)) {
		die("unterminated character class in pattern: " original)
		return ""
	}
	if(substr(s, i, 1) == "!") {
		cls = cls "^"
		i++
	}
	for(; i <= length(s); i++) {
		c = substr(s, i, 1)
		cls = cls c
		if(c == "]")
			return cls
	}
	die("unterminated character class in pattern: " original)
	return ""
}

function class_end(s, i,    c) {
	i++
	for(; i <= length(s); i++) {
		c = substr(s, i, 1)
		if(c == "]")
			return i
	}
	return 0
}

function glob_to_regex(s,    i, c, nextc, out, end) {
	out = ""
	for(i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		nextc = substr(s, i + 1, 1)

		if(c == "\\") {
			die("backslash escapes are not supported in pattern: " original)
			return ""
		} else if(c == "*") {
			if(nextc == "*") {
				if(substr(s, i + 2, 1) == "/") {
					out = out "(.*/)?"
					i += 2
				} else {
					out = out ".*"
					i++
				}
			} else {
				out = out "[^/]*"
			}
		} else if(c == "?") {
			out = out "[^/]"
		} else if(c == "[") {
			end = class_end(s, i)
			if(end == 0) {
				die("unterminated character class in pattern: " original)
				return ""
			}
			out = out translate_class(s, i)
			i = end
		} else {
			out = out escape_literal(c)
		}
	}
	return out
}

function emit(pattern,    root, dironly, body, prefix, regex) {
	original = pattern

	if(pattern == "")
		return
	if(substr(pattern, 1, 1) == "!") {
		die("negated patterns are not supported: " pattern)
		return
	}

	root = 0
	if(substr(pattern, 1, 1) == "/") {
		root = 1
		pattern = substr(pattern, 2)
	}

	dironly = 0
	if(substr(pattern, length(pattern), 1) == "/") {
		dironly = 1
		pattern = substr(pattern, 1, length(pattern) - 1)
	}

	if(pattern == "") {
		die("empty path pattern after removing anchors: " original)
		return
	}

	body = glob_to_regex(pattern)
	if(errors)
		return

	if(root || has_slash(pattern))
		prefix = "^"
	else
		prefix = "(^|.*/)"

	regex = prefix body "(/.*)?$"
	print regex
	emitted++
}

{
	line = $0
	sub("\r$", "", line)
	if(line == "")
		next
	if(substr(line, 1, 1) == "#")
		next
	emit(line)
}

END {
	if(emitted == 0) {
		print "mk-git-exclude.awk: no patterns emitted" >"/fd/2"
		errors = 1
	}
	exit errors
}
