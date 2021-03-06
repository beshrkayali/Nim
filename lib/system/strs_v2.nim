#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Default new string implementation used by Nim's core.

type
  NimStrPayloadBase = object
    cap: int

  NimStrPayload {.core.} = object
    cap: int
    data: UncheckedArray[char]

  NimStringV2 {.core.} = object
    len: int
    p: ptr NimStrPayload ## can be nil if len == 0.

const nimStrVersion {.core.} = 2

template isLiteral(s): bool = (s.p == nil) or (s.p.cap and strlitFlag) == strlitFlag

template contentSize(cap): int = cap + 1 + sizeof(NimStrPayloadBase)

template frees(s) =
  if not isLiteral(s):
    deallocShared(s.p)

proc resize(old: int): int {.inline.} =
  if old <= 0: result = 4
  elif old < 65536: result = old * 2
  else: result = old * 3 div 2 # for large arrays * 3/2 is better

proc prepareAdd(s: var NimStringV2; addlen: int) {.compilerRtl.} =
  if isLiteral(s):
    if addlen > 0:
      let oldP = s.p
      # can't mutate a literal, so we need a fresh copy here:
      s.p = cast[ptr NimStrPayload](allocShared0(contentSize(s.len + addlen)))
      s.p.cap = s.len + addlen
      if s.len > 0:
        # we are about to append, so there is no need to copy the \0 terminator:
        copyMem(unsafeAddr s.p.data[0], unsafeAddr oldP.data[0], s.len)
  else:
    let oldCap = s.p.cap and not strlitFlag
    if s.len + addlen > oldCap:
      let newCap = max(s.len + addlen, resize(oldCap))
      s.p = cast[ptr NimStrPayload](reallocShared0(s.p, contentSize(oldCap), contentSize(newCap)))
      s.p.cap = newCap

proc nimAddCharV1(s: var NimStringV2; c: char) {.compilerRtl.} =
  prepareAdd(s, 1)
  s.p.data[s.len] = c
  s.p.data[s.len+1] = '\0'
  inc s.len

proc toNimStr(str: cstring, len: int): NimStringV2 {.compilerproc.} =
  if len <= 0:
    result = NimStringV2(len: 0, p: nil)
  else:
    var p = cast[ptr NimStrPayload](allocShared0(contentSize(len)))
    p.cap = len
    if len > 0:
      # we are about to append, so there is no need to copy the \0 terminator:
      copyMem(unsafeAddr p.data[0], str, len)
    result = NimStringV2(len: len, p: p)

proc cstrToNimstr(str: cstring): NimStringV2 {.compilerRtl.} =
  if str == nil: toNimStr(str, 0)
  else: toNimStr(str, str.len)

proc nimToCStringConv(s: NimStringV2): cstring {.compilerproc, nonReloadable, inline.} =
  if s.len == 0: result = cstring""
  else: result = cstring(unsafeAddr s.p.data)

proc appendString(dest: var NimStringV2; src: NimStringV2) {.compilerproc, inline.} =
  if src.len > 0:
    # also copy the \0 terminator:
    copyMem(unsafeAddr dest.p.data[dest.len], unsafeAddr src.p.data[0], src.len+1)
    inc dest.len, src.len

proc appendChar(dest: var NimStringV2; c: char) {.compilerproc, inline.} =
  dest.p.data[dest.len] = c
  dest.p.data[dest.len+1] = '\0'
  inc dest.len

proc rawNewString(space: int): NimStringV2 {.compilerproc.} =
  # this is also 'system.newStringOfCap'.
  if space <= 0:
    result = NimStringV2(len: 0, p: nil)
  else:
    var p = cast[ptr NimStrPayload](allocShared0(contentSize(space)))
    p.cap = space
    result = NimStringV2(len: 0, p: p)

proc mnewString(len: int): NimStringV2 {.compilerproc.} =
  if len <= 0:
    result = NimStringV2(len: 0, p: nil)
  else:
    var p = cast[ptr NimStrPayload](allocShared0(contentSize(len)))
    p.cap = len
    result = NimStringV2(len: len, p: p)

proc setLengthStrV2(s: var NimStringV2, newLen: int) {.compilerRtl.} =
  if newLen == 0:
    frees(s)
    s.p = nil
  elif newLen > s.len or isLiteral(s):
    prepareAdd(s, newLen - s.len)
  s.len = newLen

proc nimAsgnStrV2(a: var NimStringV2, b: NimStringV2) {.compilerRtl.} =
  if a.p == b.p: return
  if isLiteral(b):
    # we can shallow copy literals:
    frees(a)
    a.len = b.len
    a.p = b.p
  else:
    if isLiteral(a) or  (a.p.cap and not strlitFlag) < b.len:
      # we have to allocate the 'cap' here, consider
      # 'let y = newStringOfCap(); var x = y'
      # on the other hand... These get turned into moves now.
      frees(a)
      a.p = cast[ptr NimStrPayload](allocShared0(contentSize(b.len)))
      a.p.cap = b.len
    a.len = b.len
    copyMem(unsafeAddr a.p.data[0], unsafeAddr b.p.data[0], b.len+1)

proc nimPrepareStrMutationV2(s: var NimStringV2) {.compilerRtl.} =
  if s.p != nil and (s.p.cap and strlitFlag) == strlitFlag:
    let oldP = s.p
    # can't mutate a literal, so we need a fresh copy here:
    s.p = cast[ptr NimStrPayload](allocShared0(contentSize(s.len)))
    s.p.cap = s.len
    copyMem(unsafeAddr s.p.data[0], unsafeAddr oldP.data[0], s.len+1)
