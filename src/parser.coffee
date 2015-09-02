
if not global?
  global = window

token = (regex, fn) ->
  return (src) ->
    if !(res = regex.exec(src))
      return false;
    src = src.slice(res[0].length)
    [src, fn(res)]

matchLabel = token /^([a-zA-Z_\-]+):/, (match) -> match[1]
matchOpcode = token /^[a-zA-Z]+/, (match) -> match[0]
argMatchers = [
  token /^0x[0-9a-fA-F]+/, (match) -> parseInt(match[0])
  token /^0b([01]+)/, (match) -> parseInt(match[1], 2)
  token /^-?[0-9]+(\.[0-9]+)?/, (match) -> +match[0]
  token /^[a-zA-Z][a-zA-Z_\-0-9]*/, (match) -> match[0]
  token /^\"(.*)\"/, (match) -> match[1]
  token /^\'.\'/, (match) -> match[0][1].charCodeAt(0)
  token /^\'..\'/, (match) -> (match[0][1].charCodeAt(0) << 16) + match[0][2].charCodeAt(0)
]

matchArg = (src) ->
  for matcher in argMatchers
    if (res = matcher(src))
      return res
  false


global.Parser = parse: (src) ->
  lines = [];
  lineNr = 0;

  line = {}

  prevlength = 0
  while src.length != prevlength
    prevlength = src.length

    if (res = matchLabel(src))
      src = res[0]
      line.label = res[1]
      line.opcode = "nop"

    if match = src.match(/^[ \t]+/)
      src = src.slice(match[0].length)

    if (res = matchOpcode(src))
      src = res[0]
      line.opcode = res[1]
      line.args = []

      while src[0] != "\n"
        unless match = src.match(/^[ \t]+/)
          break

        src = src.slice(match[0].length)

        unless (res = matchArg(src))
          break

        src = res[0]
        line.args.push res[1]

    if src[0] == ";"
      src = src.slice(1)

      if match = src.match(/^[ \t]+/)
        src = src.slice(match[0].length)

      if match = src.match(/^\{[^\n]*?\}/)
        src = src.slice(match[0].length)
        line.hint = (new Function("return #{match[0]};"))()

      src = src.slice(src.indexOf("\n"))

    if line.opcode?
      line.hint ?= {}
      line.lineNr = lineNr
      lines.push line
      line = {}

    if src[0] == "\n"
      lineNr++
      src = src.slice(1)
    else if src[0] != undefined
      throw new Error("Unexpected input #{src}")

  return lines
