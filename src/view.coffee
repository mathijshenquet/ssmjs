
if not global?
  global = window

$("#src").keyup (e) ->
  setTimeout View.sourceChanged, 50

$(document).delegate '#src', 'keydown', (e) ->
  keyCode = e.keyCode || e.which;

  console.log keyCode

  if keyCode == 9
    e.preventDefault()

    if window.getSelection
      sel = window.getSelection()

      if sel.getRangeAt && sel.rangeCount
        range = sel.getRangeAt(0)
        range.deleteContents()
        node = document.createTextNode("\t")
        range.insertNode(node)
        sel.collapse(node, 1)

    else if document.selection && document.selection.createRange
      range = document.selection.createRange()
      range.pasteHTML("\t")
      range.move("character", 1)
      range.select()


String::padl = (str, len) ->
  padding = Array(((len/str.length)|0) + 1).join(str)
  padding.substring(0, padding.length - this.length) + this

String::divide = (len) ->
  pieces = Math.ceil(@length / len)
  out = []

  i = 0
  while i < pieces
    out.push @slice(i*len, (i+1)*len)
    i++

  out

Number::showHex = ->

Number::showBinary = -> (if this.valueOf() == 0 then "" else @toString(2)).padl("-", 32).divide(4).join(" ")

global.View =
  addButton: (name, fn) ->
    $btn = $("<button>#{name}</button>")
    $("#ctrl").append($btn)
    $btn.click fn

  showPC: (nr) ->
    $pc = $("#pc")

    if nr == false
      $pc.hide()
    else
      $pc.animate(top: "#{(nr*20)+8}px", 200).show()

  getSrc: -> $("#src")[0].textContent

  print: (thing) ->
    console.log(thing)
    $out = $("#console-out");
    $out.append(thing).append("<hr />");

    $out[0].scrollTop = $out[0].scrollHeight

  update: (cpu) ->
    @showPC(cpu.lineNr)
    @showMem(cpu, ["hex", "int", "label", "annotation", "binary"])
    @showRegs(cpu, ["hex", "int", "label", "annotation", "binary"])

  showChar: (cp) ->
    if cp < 32
      switch cp
        when 0 then undefined
        when 10 then "\\n"
        when 13 then "\\r"
        when 9  then "\\t"
        else "\\#{cp}"
    else
      String.fromCharCode(cp)

  memoryViews:
    hex: (bank, addr) -> nr = bank.raw[addr]; (if nr == 0 then "" else nr.toString(16)).padl("-", 8).divide(2).join(" ")
    binary: (bank, addr) -> nr = bank.raw[addr]; (if nr == 0 then "" else nr.toString(2)).padl("-", 32).divide(4).join(" ")
    int: (bank, addr) -> bank.int[addr]
    float: (bank, addr) -> bank.float[addr]
    label: (bank, addr) -> bank.label[addr] ? ""
    annotation: (bank, addr) -> "<span style=color:#{bank.annote[addr]?.color ? "inherit"};>#{bank.annote[addr]?.text ? ""}</span>"
    char: (bank, addr) -> "#{@showChar(bank.u16[addr*2 + 1]) ? ""}#{@showChar(bank.u16[addr*2]) ? "\\0"}"

  memoryBankRow: (bank, addr, rows) ->
    $row = $("<tr />")

    for row in rows
      rowspan = 1
      if row == "annotation"
        if bank.annote[addr]?.ignore
          continue

        annotation = bank.annote[addr]?.text

        if annotation?
          while bank.annote[addr+(rowspan)]?.text == annotation
            bank.annote[addr+(rowspan)].ignore = true
            rowspan++

      $row.append $("<td rowspan=#{rowspan} class='mem_#{row} #{if rowspan != 1 then "mem_rowspan" else ""}'>#{@memoryViews[row](bank, addr)}</td>")

    return $row

  showMem: (cpu, rows) ->
    $tbody = $("#mem .tbody tbody")
    $tbody.empty()

    sp = cpu.regVal("sp")
    mp = cpu.regVal("mp")

    $thead = $("#mem .thead thead tr")
    $thead.empty()


    $thead.append $("<th class='mem_addr'>address</th>")
    $thead.append $("<th class='mem_mp_offset'></th>")
    for row in rows
      $thead.append $("<th class='mem_#{row}'>#{row}</th>")

    addr = 0
    while addr <= cpu.memSeen
      $row = @memoryBankRow(cpu.mem, addr, rows)

      offset =  if mp != -1 && -8 < (addr - mp) < 8
                  if addr == mp
                    "mp"
                  else if addr < mp
                    addr - mp
                  else
                    "+#{addr-mp}"
                else
                  ""

      $row.prepend $("<td class='mem_mp_offset'>#{offset}</td>")

      $row.prepend $("<td class='mem_addr'>0x#{addr.toString(16).padl('0', 8)}</td>")

      $tbody.append($row)

      if addr == mp
        $row.addClass("mp")

      if addr > sp
        $row.addClass("zombie_mem")


      if cpu.mem.written[addr]
        $row.addClass("ping-write")
      else if cpu.mem.read[addr]
        $row.addClass("ping-read")

      addr++

    cpu.mem.written = {}
    cpu.mem.read = {}

  showRegs: (cpu, rows) ->
    $tbody = $("#regs .tbody tbody")
    $tbody.empty()

    $thead = $("#regs .thead thead tr")
    $thead.empty()

    $thead.append $("<th class='mem_addr'>address</th>")
    for row in rows
      $thead.append $("<th class='mem_#{row}'>#{row}</th>")


    id = 0
    while id < cpu.regCount
      $row = @memoryBankRow(cpu.reg, id, rows)
      $row.prepend $("<td class='mem_addr'>#{cpu.regName(id) ? "R#{id}"}</td>")

      $tbody.append($row)

      if cpu.reg.written[id]
        $row.addClass("ping-write")
      else if cpu.reg.read[id]
        $row.addClass("ping-read")

      id++

    cpu.reg.written = {}
    cpu.reg.read = {}


  sourceChanged: ->
