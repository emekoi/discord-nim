## 
##  Copyright (c) 2018 emekoi
##
##  This library is free software; you can redistribute it and/or modify it
##  under the terms of the MIT license. See LICENSE for details.
##

type
  UnwrapError* = object of Exception

  Option*[T] = object
    case isSome*: bool
      of true:  raw: T
      of false: discard

proc `.isNone`*(o: Option): bool =
  return not o.isSome

proc `.raw`*[T](o: Option[T]): ptr T =
  if o.isSome:
    return o.raw.unsafeAddr
  return nil

proc `$`*(o: Option): string =
  if o.isSome: result = $o.raw
  else: result = "None"

proc unwrap*[T](o: Option[T]): T =
  if o.isSome:
    result = o.raw
  else:
    raise newException(UnwrapError, "unable to unwrap None value")

proc None*(T: typedesc): Option[T] =
  return Option[T](isSome: false)

proc Some*[T](v: T): Option[T] =
  return Option(isSome: true, raw: v)