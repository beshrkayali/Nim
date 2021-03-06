#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


# import typetraits
# strs already imported allocateds for us.

proc supportsCopyMem(t: typedesc): bool {.magic: "TypeTrait".}

## Default seq implementation used by Nim's core.
type

  NimSeqPayloadBase = object
    cap: int

  NimSeqPayload[T] = object
    cap: int
    data: UncheckedArray[T]

  NimSeqV2*[T] = object
    len: int
    p: ptr NimSeqPayload[T]

const nimSeqVersion {.core.} = 2

# XXX make code memory safe for overflows in '*'

proc newSeqPayload(cap, elemSize: int): pointer {.compilerRtl, raises: [].} =
  # we have to use type erasure here as Nim does not support generic
  # compilerProcs. Oh well, this will all be inlined anyway.
  if cap > 0:
    var p = cast[ptr NimSeqPayloadBase](allocShared0(cap * elemSize + sizeof(NimSeqPayloadBase)))
    p.cap = cap
    result = p
  else:
    result = nil

proc prepareSeqAdd(len: int; p: pointer; addlen, elemSize: int): pointer {.
    noSideEffect, raises: [].} =
  {.noSideEffect.}:
    template `+!`(p: pointer, s: int): pointer =
      cast[pointer](cast[int](p) +% s)

    const headerSize = sizeof(NimSeqPayloadBase)
    if addlen <= 0:
      result = p
    elif p == nil:
      result = newSeqPayload(len+addlen, elemSize)
    else:
      # Note: this means we cannot support things that have internal pointers as
      # they get reallocated here. This needs to be documented clearly.
      var p = cast[ptr NimSeqPayloadBase](p)
      let oldCap = p.cap and not strlitFlag
      let newCap = max(resize(oldCap), len+addlen)
      if (p.cap and strlitFlag) == strlitFlag:
        var q = cast[ptr NimSeqPayloadBase](allocShared0(headerSize + elemSize * newCap))
        copyMem(q +! headerSize, p +! headerSize, len * elemSize)
        q.cap = newCap
        result = q
      else:
        let oldSize = headerSize + elemSize * oldCap
        let newSize = headerSize + elemSize * newCap
        var q = cast[ptr NimSeqPayloadBase](reallocShared0(p, oldSize, newSize))
        q.cap = newCap
        result = q

proc shrink*[T](x: var seq[T]; newLen: Natural) =
  when nimvm:
    setLen(x, newLen)
  else:
    mixin `=destroy`
    sysAssert newLen <= x.len, "invalid newLen parameter for 'shrink'"
    when not supportsCopyMem(T):
      for i in countdown(x.len - 1, newLen):
        `=destroy`(x[i])
    # XXX This is wrong for const seqs that were moved into 'x'!
    cast[ptr NimSeqV2[T]](addr x).len = newLen

proc grow*[T](x: var seq[T]; newLen: Natural; value: T) =
  let oldLen = x.len
  if newLen <= oldLen: return
  var xu = cast[ptr NimSeqV2[T]](addr x)
  if xu.p == nil or xu.p.cap < newLen:
    xu.p = cast[typeof(xu.p)](prepareSeqAdd(oldLen, xu.p, newLen - oldLen, sizeof(T)))
  xu.len = newLen
  for i in oldLen .. newLen-1:
    xu.p.data[i] = value

proc add*[T](x: var seq[T]; value: sink T) {.magic: "AppendSeqElem", noSideEffect.} =
  ## Generic proc for adding a data item `y` to a container `x`.
  ##
  ## For containers that have an order, `add` means *append*. New generic
  ## containers should also call their adding proc `add` for consistency.
  ## Generic code becomes much easier to write if the Nim naming scheme is
  ## respected.
  let oldLen = x.len
  var xu = cast[ptr NimSeqV2[T]](addr x)
  if xu.p == nil or xu.p.cap < oldLen+1:
    xu.p = cast[typeof(xu.p)](prepareSeqAdd(oldLen, xu.p, 1, sizeof(T)))
  xu.len = oldLen+1
  xu.p.data[oldLen] = value

proc setLen[T](s: var seq[T], newlen: Natural) =
  {.noSideEffect.}:
    if newlen < s.len:
      shrink(s, newlen)
    else:
      let oldLen = s.len
      if newlen <= oldLen: return
      var xu = cast[ptr NimSeqV2[T]](addr s)
      if xu.p == nil or xu.p.cap < newlen:
        xu.p = cast[typeof(xu.p)](prepareSeqAdd(oldLen, xu.p, newlen - oldLen, sizeof(T)))
      xu.len = newlen
