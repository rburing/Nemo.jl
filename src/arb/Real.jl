###############################################################################
#
#   arb.jl : Arb real numbers
#
#   Copyright (C) 2015 Tommy Hofmann
#   Copyright (C) 2015 Fredrik Johansson
#
###############################################################################

import Base: ceil, isinteger

export add_error!, ball, radius, midpoint, contains, contains_zero, contains_negative,
       contains_positive, contains_nonnegative, contains_nonpositive, convert,
       iszero, is_nonzero, is_exact, is_positive, isfinite, is_nonnegative,
       is_negative, is_nonpositive, add!, mul!, sub!, div!, overlaps,
       unique_integer, accuracy_bits, trim, ldexp, setunion, setintersection,
       const_pi, const_e, const_log2, const_log10, const_euler, const_catalan,
       const_khinchin, const_glaisher, floor, ceil, hypot, rsqrt, sqrt1pm1,
       sqrtpos, root, log, log1p, expm1, sin, cos, sinpi, cospi, tan, cot,
       tanpi, cotpi, sinh, cosh, tanh, coth, atan, asin, acos, atanh, asinh,
       acosh, gamma, lgamma, rgamma, digamma, gamma_regularized, gamma_lower,
       gamma_lower_regularized, zeta, sincos, sincospi, sinhcosh, atan2, agm,
       factorial, binomial, fibonacci, bernoulli, rising_factorial,
       rising_factorial2, polylog, chebyshev_t, chebyshev_t2, chebyshev_u,
       chebyshev_u2, bell, numpart, lindep, airy_ai, airy_bi, airy_ai_prime,
       airy_bi_prime, canonical_unit, simplest_rational_inside

###############################################################################
#
#   Basic manipulation
#
###############################################################################

elem_type(::Type{RealField}) = RealElem

parent_type(::Type{RealElem}) = RealField

base_ring(R::RealField) = Union{}

base_ring(x::RealElem) = Union{}

parent(x::RealElem) = RealField()

is_domain_type(::Type{RealElem}) = true

is_exact_type(::Type{RealElem}) = false

zero(R::RealField) = R(0)

one(R::RealField) = R(1)

# TODO: Add hash (and document under arb basic functionality)

@doc Markdown.doc"""
    accuracy_bits(x::RealElem)

Return the relative accuracy of $x$ measured in bits, capped between
`typemax(Int)` and `-typemax(Int)`.
"""
function accuracy_bits(x::RealElem)
  return ccall((:arb_rel_accuracy_bits, libarb), Int, (Ref{RealElem},), x)
end

function deepcopy_internal(a::RealElem, dict::IdDict)
  b = parent(a)()
  ccall((:arb_set, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}), b, a)
  return b
end

function canonical_unit(x::RealElem)
   return x
end

function check_parent(a::RealElem, b::RealElem)
   return true
end

characteristic(::RealField) = 0

################################################################################
#
#  Conversions
#
################################################################################

@doc Markdown.doc"""
    Float64(x::RealElem, round::RoundingMode=RoundNearest)

Converts $x$ to a `Float64`, rounded in the direction specified by $round$.
For `RoundNearest` the return value approximates the midpoint of $x$. For
`RoundDown` or `RoundUp` the return value is a lower bound or upper bound for
all values in $x$.
"""
function Float64(x::RealElem, round::RoundingMode=RoundNearest)
  t = _arb_get_arf(x, round)
  return _arf_get_d(t, round)
end

@doc Markdown.doc"""
    BigFloat(x::RealElem, round::RoundingMode=RoundNearest)

Converts $x$ to a `BigFloat` of the currently used precision, rounded in the
direction specified by $round$. For `RoundNearest` the return value
approximates the midpoint of $x$. For `RoundDown` or `RoundUp` the return
value is a lower bound or upper bound for all values in $x$.
"""
function BigFloat(x::RealElem, round::RoundingMode=RoundNearest)
  t = _arb_get_arf(x, round)
  return _arf_get_mpfr(t, round)
end

function _arb_get_arf(x::RealElem, ::RoundingMode{:Nearest})
  t = arf_struct()
  GC.@preserve x begin
    t1 = ccall((:arb_mid_ptr, libarb), Ptr{arf_struct},
               (Ref{RealElem}, ),
               x)
    ccall((:arf_set, libarb), Nothing,
          (Ref{arf_struct}, Ptr{arf_struct}),
          t, t1)
  end
  return t
end

for (b, f) in ((RoundingMode{:Down}, :arb_get_lbound_arf),
               (RoundingMode{:Up}, :arb_get_ubound_arf))
  @eval begin
    function _arb_get_arf(x::RealElem, ::$b, prec = precision(Balls))
      t = arf_struct()
      ccall(($(string(f)), libarb), Nothing,
            (Ref{arf_struct}, Ref{RealElem}, Int),
            t, x, prec)
      return t
    end
  end
end

function convert(::Type{Float64}, x::RealElem)
    return Float64(x)
end

function convert(::Type{BigFloat}, x::RealElem)
    return BigFloat(x)
end

@doc Markdown.doc"""
    ZZRingElem(x::RealElem)

Return $x$ as an `ZZRingElem` if it represents an unique integer, else throws an
error.
"""
function ZZRingElem(x::RealElem)
   if is_exact(x)
      ok, z = unique_integer(x)
      ok && return z
   end
   error("Argument must represent a unique integer")
end

BigInt(x::RealElem) = BigInt(ZZRingElem(x))

function (::Type{T})(x::RealElem) where {T <: Integer}
  typemin(T) <= x <= typemax(T) ||
      error("Argument does not fit inside datatype.")
  return T(ZZRingElem(x))
end

################################################################################
#
#  String I/O
#
################################################################################

function native_string(x::RealElem)
   d = ceil(precision(Balls) * 0.30102999566398119521)
   cstr = ccall((:arb_get_str, libarb), Ptr{UInt8},
                (Ref{RealElem}, Int, UInt),
                x, Int(d), UInt(0))
   res = unsafe_string(cstr)
   ccall((:flint_free, libflint), Nothing,
         (Ptr{UInt8},),
         cstr)
   return res
end

function expressify(x::RealElem; context = nothing)
   if is_exact(x) && is_negative(x)
      # TODO is_exact does not imply it is printed without radius
      return Expr(:call, :-, native_string(-x))
   else
      return native_string(x)
   end
end

function show(io::IO, x::RealField)
  print(io, "Real Field with ")
  print(io, precision(x))
  print(io, " bits of precision and error bounds")
end

function show(io::IO, x::RealElem)
   print(io, native_string(x))
end

################################################################################
#
#  Containment
#
################################################################################

@doc Markdown.doc"""
    overlaps(x::RealElem, y::RealElem)

Returns `true` if any part of the ball $x$ overlaps any part of the ball $y$,
otherwise return `false`.
"""
function overlaps(x::RealElem, y::RealElem)
  r = ccall((:arb_overlaps, libarb), Cint, (Ref{RealElem}, Ref{RealElem}), x, y)
  return Bool(r)
end

#function contains(x::RealElem, y::arf)
#  r = ccall((:arb_contains_arf, libarb), Cint, (Ref{RealElem}, Ref{arf}), x, y)
#  return Bool(r)
#end

@doc Markdown.doc"""
    contains(x::RealElem, y::QQFieldElem)

Returns `true` if the ball $x$ contains the given rational value, otherwise
return `false`.
"""
function contains(x::RealElem, y::QQFieldElem)
  r = ccall((:arb_contains_fmpq, libarb), Cint, (Ref{RealElem}, Ref{QQFieldElem}), x, y)
  return Bool(r)
end

@doc Markdown.doc"""
    contains(x::RealElem, y::ZZRingElem)

Returns `true` if the ball $x$ contains the given integer value, otherwise
return `false`.
"""
function contains(x::RealElem, y::ZZRingElem)
  r = ccall((:arb_contains_fmpz, libarb), Cint, (Ref{RealElem}, Ref{ZZRingElem}), x, y)
  return Bool(r)
end

function contains(x::RealElem, y::Int)
  r = ccall((:arb_contains_si, libarb), Cint, (Ref{RealElem}, Int), x, y)
  return Bool(r)
end

@doc Markdown.doc"""
    contains(x::RealElem, y::Integer)

Returns `true` if the ball $x$ contains the given integer value, otherwise
return `false`.
"""
contains(x::RealElem, y::Integer) = contains(x, ZZRingElem(y))

@doc Markdown.doc"""
    contains(x::RealElem, y::Rational{T}) where {T <: Integer}

Returns `true` if the ball $x$ contains the given rational value, otherwise
return `false`.
"""
contains(x::RealElem, y::Rational{T}) where {T <: Integer} = contains(x, QQFieldElem(y))

@doc Markdown.doc"""
    contains(x::RealElem, y::BigFloat)

Returns `true` if the ball $x$ contains the given floating point value,
otherwise return `false`.
"""
function contains(x::RealElem, y::BigFloat)
  r = ccall((:arb_contains_mpfr, libarb), Cint,
              (Ref{RealElem}, Ref{BigFloat}), x, y)
  return Bool(r)
end

@doc Markdown.doc"""
    contains(x::RealElem, y::RealElem)

Returns `true` if the ball $x$ contains the ball $y$, otherwise return
`false`.
"""
function contains(x::RealElem, y::RealElem)
  r = ccall((:arb_contains, libarb), Cint, (Ref{RealElem}, Ref{RealElem}), x, y)
  return Bool(r)
end

@doc Markdown.doc"""
    contains_zero(x::RealElem)

Returns `true` if the ball $x$ contains zero, otherwise return `false`.
"""
function contains_zero(x::RealElem)
   r = ccall((:arb_contains_zero, libarb), Cint, (Ref{RealElem}, ), x)
   return Bool(r)
end

@doc Markdown.doc"""
    contains_negative(x::RealElem)

Returns `true` if the ball $x$ contains any negative value, otherwise return
`false`.
"""
function contains_negative(x::RealElem)
   r = ccall((:arb_contains_negative, libarb), Cint, (Ref{RealElem}, ), x)
   return Bool(r)
end

@doc Markdown.doc"""
    contains_positive(x::RealElem)

Returns `true` if the ball $x$ contains any positive value, otherwise return
`false`.
"""
function contains_positive(x::RealElem)
   r = ccall((:arb_contains_positive, libarb), Cint, (Ref{RealElem}, ), x)
   return Bool(r)
end

@doc Markdown.doc"""
    contains_nonnegative(x::RealElem)

Returns `true` if the ball $x$ contains any nonnegative value, otherwise
return `false`.
"""
function contains_nonnegative(x::RealElem)
   r = ccall((:arb_contains_nonnegative, libarb), Cint, (Ref{RealElem}, ), x)
   return Bool(r)
end

@doc Markdown.doc"""
    contains_nonpositive(x::RealElem)

Returns `true` if the ball $x$ contains any nonpositive value, otherwise
return `false`.
"""
function contains_nonpositive(x::RealElem)
   r = ccall((:arb_contains_nonpositive, libarb), Cint, (Ref{RealElem}, ), x)
   return Bool(r)
end

################################################################################
#
#  Comparison
#
################################################################################

@doc Markdown.doc"""
    isequal(x::RealElem, y::RealElem)

Return `true` if the balls $x$ and $y$ are precisely equal, i.e. have the
same midpoints and radii.
"""
function isequal(x::RealElem, y::RealElem)
  r = ccall((:arb_equal, libarb), Cint, (Ref{RealElem}, Ref{RealElem}), x, y)
  return Bool(r)
end

function ==(x::RealElem, y::RealElem)
    return Bool(ccall((:arb_eq, libarb), Cint, (Ref{RealElem}, Ref{RealElem}), x, y))
end

function !=(x::RealElem, y::RealElem)
    return Bool(ccall((:arb_ne, libarb), Cint, (Ref{RealElem}, Ref{RealElem}), x, y))
end

function isless(x::RealElem, y::RealElem)
    return Bool(ccall((:arb_lt, libarb), Cint, (Ref{RealElem}, Ref{RealElem}), x, y))
end

function <=(x::RealElem, y::RealElem)
    return Bool(ccall((:arb_le, libarb), Cint, (Ref{RealElem}, Ref{RealElem}), x, y))
end

==(x::RealElem, y::Int) = x == RealElem(y)
!=(x::RealElem, y::Int) = x != RealElem(y)
<=(x::RealElem, y::Int) = x <= RealElem(y)
<(x::RealElem, y::Int) = x < RealElem(y)

==(x::Int, y::RealElem) = RealElem(x) == y
!=(x::Int, y::RealElem) = RealElem(x) != y
<=(x::Int, y::RealElem) = RealElem(x) <= y
<(x::Int, y::RealElem) = RealElem(x) < y

==(x::RealElem, y::ZZRingElem) = x == RealElem(y)
!=(x::RealElem, y::ZZRingElem) = x != RealElem(y)
<=(x::RealElem, y::ZZRingElem) = x <= RealElem(y)
<(x::RealElem, y::ZZRingElem) = x < RealElem(y)

==(x::ZZRingElem, y::RealElem) = RealElem(x) == y
!=(x::ZZRingElem, y::RealElem) = RealElem(x) != y
<=(x::ZZRingElem, y::RealElem) = RealElem(x) <= y
<(x::ZZRingElem, y::RealElem) = RealElem(x) < y

==(x::RealElem, y::Integer) = x == ZZRingElem(y)
!=(x::RealElem, y::Integer) = x != ZZRingElem(y)
<=(x::RealElem, y::Integer) = x <= ZZRingElem(y)
<(x::RealElem, y::Integer) = x < ZZRingElem(y)


==(x::Integer, y::RealElem) = ZZRingElem(x) == y
!=(x::Integer, y::RealElem) = ZZRingElem(x) != y
<=(x::Integer, y::RealElem) = ZZRingElem(x) <= y
<(x::Integer, y::RealElem) = ZZRingElem(x) < y

==(x::RealElem, y::Float64) = x == RealElem(y)
!=(x::RealElem, y::Float64) = x != RealElem(y)
<=(x::RealElem, y::Float64) = x <= RealElem(y)
<(x::RealElem, y::Float64) = x < RealElem(y)

==(x::Float64, y::RealElem) = RealElem(x) == y
!=(x::Float64, y::RealElem) = RealElem(x) != y
<=(x::Float64, y::RealElem) = RealElem(x) <= y
<(x::Float64, y::RealElem) = RealElem(x) < y

==(x::RealElem, y::BigFloat) = x == RealElem(y)
!=(x::RealElem, y::BigFloat) = x != RealElem(y)
<=(x::RealElem, y::BigFloat) = x <= RealElem(y)
<(x::RealElem, y::BigFloat) = x < RealElem(y)

==(x::BigFloat, y::RealElem) = RealElem(x) == y
!=(x::BigFloat, y::RealElem) = RealElem(x) != y
<=(x::BigFloat, y::RealElem) = RealElem(x) <= y
<(x::BigFloat, y::RealElem) = RealElem(x) < y

==(x::RealElem, y::QQFieldElem) = x == RealElem(y, precision(Balls))
!=(x::RealElem, y::QQFieldElem) = x != RealElem(y, precision(Balls))
<=(x::RealElem, y::QQFieldElem) = x <= RealElem(y, precision(Balls))
<(x::RealElem, y::QQFieldElem) = x < RealElem(y, precision(Balls))

==(x::QQFieldElem, y::RealElem) = RealElem(x, precision(Balls)) == y
!=(x::QQFieldElem, y::RealElem) = RealElem(x, precision(Balls)) != y
<=(x::QQFieldElem, y::RealElem) = RealElem(x, precision(Balls)) <= y
<(x::QQFieldElem, y::RealElem) = RealElem(x, precision(Balls)) < y

==(x::RealElem, y::Rational{T}) where {T <: Integer} = x == QQFieldElem(y)
!=(x::RealElem, y::Rational{T}) where {T <: Integer} = x != QQFieldElem(y)
<=(x::RealElem, y::Rational{T}) where {T <: Integer} = x <= QQFieldElem(y)
<(x::RealElem, y::Rational{T}) where {T <: Integer} = x < QQFieldElem(y)

==(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) == y
!=(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) != y
<=(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) <= y
<(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) < y

################################################################################
#
#  Predicates
#
################################################################################

function is_unit(x::RealElem)
   !contains_zero(x)
end

@doc Markdown.doc"""
    iszero(x::RealElem)

Return `true` if $x$ is certainly zero, otherwise return `false`.
"""
function iszero(x::RealElem)
   return Bool(ccall((:arb_is_zero, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    is_nonzero(x::RealElem)

Return `true` if $x$ is certainly not equal to zero, otherwise return
`false`.
"""
function is_nonzero(x::RealElem)
   return Bool(ccall((:arb_is_nonzero, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    isone(x::RealElem)

Return `true` if $x$ is certainly not equal to oneo, otherwise return
`false`.
"""
function isone(x::RealElem)
   return Bool(ccall((:arb_is_one, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    isfinite(x::RealElem)

Return `true` if $x$ is finite, i.e. having finite midpoint and radius,
otherwise return `false`.
"""
function isfinite(x::RealElem)
   return Bool(ccall((:arb_is_finite, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    is_exact(x::RealElem)

Return `true` if $x$ is exact, i.e. has zero radius, otherwise return
`false`.
"""
function is_exact(x::RealElem)
   return Bool(ccall((:arb_is_exact, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    isinteger(x::RealElem)

Return `true` if $x$ is an exact integer, otherwise return `false`.
"""
function isinteger(x::RealElem)
   return Bool(ccall((:arb_is_int, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    is_positive(x::RealElem)

Return `true` if $x$ is certainly positive, otherwise return `false`.
"""
function is_positive(x::RealElem)
   return Bool(ccall((:arb_is_positive, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    is_nonnegative(x::RealElem)

Return `true` if $x$ is certainly nonnegative, otherwise return `false`.
"""
function is_nonnegative(x::RealElem)
   return Bool(ccall((:arb_is_nonnegative, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    is_negative(x::RealElem)

Return `true` if $x$ is certainly negative, otherwise return `false`.
"""
function is_negative(x::RealElem)
   return Bool(ccall((:arb_is_negative, libarb), Cint, (Ref{RealElem},), x))
end

@doc Markdown.doc"""
    is_nonpositive(x::RealElem)

Return `true` if $x$ is certainly nonpositive, otherwise return `false`.
"""
function is_nonpositive(x::RealElem)
   return Bool(ccall((:arb_is_nonpositive, libarb), Cint, (Ref{RealElem},), x))
end

################################################################################
#
#  Parts of numbers
#
################################################################################

@doc Markdown.doc"""
    ball(x::RealElem, y::RealElem)

Constructs an Arb ball enclosing $x_m \pm (|x_r| + |y_m| + |y_r|)$, given the
pair $(x, y) = (x_m \pm x_r, y_m \pm y_r)$.
"""
function ball(mid::RealElem, rad::RealElem)
  z = RealElem(mid, rad)
  return z
end

@doc Markdown.doc"""
    radius(x::RealElem)

Return the radius of the ball $x$ as an Arb ball.
"""
function radius(x::RealElem)
  z = RealElem()
  ccall((:arb_get_rad_arb, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}), z, x)
  return z
end

@doc Markdown.doc"""
    midpoint(x::RealElem)

Return the midpoint of the ball $x$ as an Arb ball.
"""
function midpoint(x::RealElem)
  z = RealElem()
  ccall((:arb_get_mid_arb, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}), z, x)
  return z
end

@doc Markdown.doc"""
    add_error!(x::RealElem, y::RealElem)

Adds the absolute values of the midpoint and radius of $y$ to the radius of $x$.
"""
function add_error!(x::RealElem, y::RealElem)
  ccall((:arb_add_error, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}), x, y)
end

################################################################################
#
#  Unary operations
#
################################################################################

function -(x::RealElem)
  z = RealElem()
  ccall((:arb_neg, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}), z, x)
  return z
end

################################################################################
#
#  Binary operations
#
################################################################################

for (s,f) in ((:+,"arb_add"), (:*,"arb_mul"), (://, "arb_div"), (:-,"arb_sub"))
  @eval begin
    function ($s)(x::RealElem, y::RealElem, prec = precision(Balls))
      z = RealElem()
      ccall(($f, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int),
                           z, x, y, prec)
      return z
    end
  end
end

for (f,s) in ((:+, "add"), (:*, "mul"))
  @eval begin
    #function ($f)(x::RealElem, y::arf)
    #  z = RealElem()
    #  ccall(($("arb_"*s*"_arf"), libarb), Nothing,
    #              (Ref{RealElem}, Ref{RealElem}, Ref{arf}, Int),
    #              z, x, y, precision(Balls))
    #  return z
    #end

    #($f)(x::arf, y::RealElem) = ($f)(y, x)

    function ($f)(x::RealElem, y::UInt, prec = precision(Balls))
      z = RealElem()
      ccall(($("arb_"*s*"_ui"), libarb), Nothing,
                  (Ref{RealElem}, Ref{RealElem}, UInt, Int),
                  z, x, y, prec)
      return z
    end

    ($f)(x::UInt, y::RealElem) = ($f)(y, x)

    function ($f)(x::RealElem, y::Int, prec = precision(Balls))
      z = RealElem()
      ccall(($("arb_"*s*"_si"), libarb), Nothing,
      (Ref{RealElem}, Ref{RealElem}, Int, Int), z, x, y, prec)
      return z
    end

    ($f)(x::Int, y::RealElem, prec = precision(Balls)) = ($f)(y, x, prec)

    function ($f)(x::RealElem, y::ZZRingElem, prec = precision(Balls))
      z = RealElem()
      ccall(($("arb_"*s*"_fmpz"), libarb), Nothing,
                  (Ref{RealElem}, Ref{RealElem}, Ref{ZZRingElem}, Int),
                  z, x, y, prec)
      return z
    end

    ($f)(x::ZZRingElem, y::RealElem, prec = precision(Balls)) = ($f)(y, x, prec)
  end
end

#function -(x::RealElem, y::arf)
#  z = RealElem()
#  ccall((:arb_sub_arf, libarb), Nothing,
#              (Ref{RealElem}, Ref{RealElem}, Ref{arf}, Int), z, x, y, precision(Balls))
#  return z
#end

#-(x::arf, y::RealElem) = -(y - x)

function -(x::RealElem, y::UInt, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_sub_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Int), z, x, y, prec)
  return z
end

-(x::UInt, y::RealElem) = -(y - x)

function -(x::RealElem, y::Int, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_sub_si, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Int, Int), z, x, y, prec)
  return z
end

-(x::Int, y::RealElem) = -(y - x)

function -(x::RealElem, y::ZZRingElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_sub_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{ZZRingElem}, Int),
              z, x, y, prec)
  return z
end

-(x::ZZRingElem, y::RealElem) = -(y-x)

+(x::RealElem, y::Integer) = x + ZZRingElem(y)

-(x::RealElem, y::Integer) = x - ZZRingElem(y)

*(x::RealElem, y::Integer) = x*ZZRingElem(y)

//(x::RealElem, y::Integer) = x//ZZRingElem(y)

+(x::Integer, y::RealElem) = ZZRingElem(x) + y

-(x::Integer, y::RealElem) = ZZRingElem(x) - y

*(x::Integer, y::RealElem) = ZZRingElem(x)*y

//(x::Integer, y::RealElem) = ZZRingElem(x)//y

#function //(x::RealElem, y::arf)
#  z = RealElem()
#  ccall((:arb_div_arf, libarb), Nothing,
#              (Ref{RealElem}, Ref{RealElem}, Ref{arf}, Int), z, x, y, precision(Balls))
#  return z
#end

function //(x::RealElem, y::UInt, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_div_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Int), z, x, y, prec)
  return z
end

function //(x::RealElem, y::Int, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_div_si, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Int, Int), z, x, y, prec)
  return z
end

function //(x::RealElem, y::ZZRingElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_div_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{ZZRingElem}, Int),
              z, x, y, prec)
  return z
end

function //(x::UInt, y::RealElem, prec = precision(Balls))
  z = parent(y)()
  ccall((:arb_ui_div, libarb), Nothing,
              (Ref{RealElem}, UInt, Ref{RealElem}, Int), z, x, y, prec)
  return z
end

function //(x::Int, y::RealElem, prec = precision(Balls))
  z = parent(y)()
  t = RealElem(x)
  ccall((:arb_div, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, t, y, prec)
  return z
end

function //(x::ZZRingElem, y::RealElem, prec = precision(Balls))
  z = parent(y)()
  t = RealElem(x)
  ccall((:arb_div, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, t, y, prec)
  return z
end

function ^(x::RealElem, y::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_pow, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, x, y, prec)
  return z
end

function ^(x::RealElem, y::ZZRingElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_pow_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{ZZRingElem}, Int),
              z, x, y, prec)
  return z
end

^(x::RealElem, y::Integer, prec = precision(Balls)) = ^(x, ZZRingElem(y), prec)

function ^(x::RealElem, y::UInt, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_pow_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Int), z, x, y, prec)
  return z
end

function ^(x::RealElem, y::QQFieldElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_pow_fmpq, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{QQFieldElem}, Int),
              z, x, y, prec)
  return z
end

+(x::QQFieldElem, y::RealElem) = parent(y)(x) + y
+(x::RealElem, y::QQFieldElem) = x + parent(x)(y)
-(x::QQFieldElem, y::RealElem) = parent(y)(x) - y
//(x::RealElem, y::QQFieldElem) = x//parent(x)(y)
//(x::QQFieldElem, y::RealElem) = parent(y)(x)//y
-(x::RealElem, y::QQFieldElem) = x - parent(x)(y)
*(x::QQFieldElem, y::RealElem) = parent(y)(x) * y
*(x::RealElem, y::QQFieldElem) = x * parent(x)(y)
^(x::QQFieldElem, y::RealElem) = parent(y)(x) ^ y

+(x::Float64, y::RealElem) = parent(y)(x) + y
+(x::RealElem, y::Float64) = x + parent(x)(y)
-(x::Float64, y::RealElem) = parent(y)(x) - y
//(x::RealElem, y::Float64) = x//parent(x)(y)
//(x::Float64, y::RealElem) = parent(y)(x)//y
-(x::RealElem, y::Float64) = x - parent(x)(y)
*(x::Float64, y::RealElem) = parent(y)(x) * y
*(x::RealElem, y::Float64) = x * parent(x)(y)
^(x::Float64, y::RealElem) = parent(y)(x) ^ y
^(x::RealElem, y::Float64) = x ^ parent(x)(y)

+(x::BigFloat, y::RealElem) = parent(y)(x) + y
+(x::RealElem, y::BigFloat) = x + parent(x)(y)
-(x::BigFloat, y::RealElem) = parent(y)(x) - y
//(x::RealElem, y::BigFloat) = x//parent(x)(y)
//(x::BigFloat, y::RealElem) = parent(y)(x)//y
-(x::RealElem, y::BigFloat) = x - parent(x)(y)
*(x::BigFloat, y::RealElem) = parent(y)(x) * y
*(x::RealElem, y::BigFloat) = x * parent(x)(y)
^(x::BigFloat, y::RealElem) = parent(y)(x) ^ y
^(x::RealElem, y::BigFloat) = x ^ parent(x)(y)

+(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) + y
+(x::RealElem, y::Rational{T}) where {T <: Integer} = x + QQFieldElem(y)
-(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) - y
-(x::RealElem, y::Rational{T}) where {T <: Integer} = x - QQFieldElem(y)
//(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x)//y
//(x::RealElem, y::Rational{T}) where {T <: Integer} = x//QQFieldElem(y)
*(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) * y
*(x::RealElem, y::Rational{T}) where {T <: Integer} = x * QQFieldElem(y)
^(x::Rational{T}, y::RealElem) where {T <: Integer} = QQFieldElem(x) ^ y
^(x::RealElem, y::Rational{T}) where {T <: Integer} = x ^ QQFieldElem(y)

/(x::RealElem, y::RealElem) = x // y
/(x::ZZRingElem, y::RealElem) = x // y
/(x::RealElem, y::ZZRingElem) = x // y
/(x::Int, y::RealElem) = x // y
/(x::RealElem, y::Int) = x // y
/(x::UInt, y::RealElem) = x // y
/(x::RealElem, y::UInt) = x // y
/(x::QQFieldElem, y::RealElem) = x // y
/(x::RealElem, y::QQFieldElem) = x // y
/(x::Float64, y::RealElem) = x // y
/(x::RealElem, y::Float64) = x // y
/(x::BigFloat, y::RealElem) = x // y
/(x::RealElem, y::BigFloat) = x // y
/(x::Rational{T}, y::RealElem) where {T <: Integer} = x // y
/(x::RealElem, y::Rational{T}) where {T <: Integer} = x // y

divexact(x::RealElem, y::RealElem; check::Bool=true) = x // y
divexact(x::ZZRingElem, y::RealElem; check::Bool=true) = x // y
divexact(x::RealElem, y::ZZRingElem; check::Bool=true) = x // y
divexact(x::Int, y::RealElem; check::Bool=true) = x // y
divexact(x::RealElem, y::Int; check::Bool=true) = x // y
divexact(x::UInt, y::RealElem; check::Bool=true) = x // y
divexact(x::RealElem, y::UInt; check::Bool=true) = x // y
divexact(x::QQFieldElem, y::RealElem; check::Bool=true) = x // y
divexact(x::RealElem, y::QQFieldElem; check::Bool=true) = x // y
divexact(x::Float64, y::RealElem; check::Bool=true) = x // y
divexact(x::RealElem, y::Float64; check::Bool=true) = x // y
divexact(x::BigFloat, y::RealElem; check::Bool=true) = x // y
divexact(x::RealElem, y::BigFloat; check::Bool=true) = x // y
divexact(x::Rational{T}, y::RealElem; check::Bool=true) where {T <: Integer} = x // y
divexact(x::RealElem, y::Rational{T}; check::Bool=true) where {T <: Integer} = x // y

################################################################################
#
#  Absolute value
#
################################################################################

function abs(x::RealElem)
  z = RealElem()
  ccall((:arb_abs, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}), z, x)
  return z
end

################################################################################
#
#  Inverse
#
################################################################################

function inv(x::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_inv, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
  return parent(x)(z)
end

################################################################################
#
#  Shifting
#
################################################################################

function ldexp(x::RealElem, y::Int)
  z = RealElem()
  ccall((:arb_mul_2exp_si, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Int), z, x, y)
  return z
end

function ldexp(x::RealElem, y::ZZRingElem)
  z = RealElem()
  ccall((:arb_mul_2exp_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{ZZRingElem}), z, x, y)
  return z
end

################################################################################
#
#  Miscellaneous
#
################################################################################

@doc Markdown.doc"""
    trim(x::RealElem)

Return an `arb` interval containing $x$ but which may be more economical,
by rounding off insignificant bits from the midpoint.
"""
function trim(x::RealElem)
  z = RealElem()
  ccall((:arb_trim, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}), z, x)
  return z
end

@doc Markdown.doc"""
    unique_integer(x::RealElem)

Return a pair where the first value is a boolean and the second is an `ZZRingElem`
integer. The boolean indicates whether the interval $x$ contains a unique
integer. If this is the case, the second return value is set to this unique
integer.
"""
function unique_integer(x::RealElem)
  z = ZZRingElem()
  unique = ccall((:arb_get_unique_fmpz, libarb), Int,
    (Ref{ZZRingElem}, Ref{RealElem}), z, x)
  return (unique != 0, z)
end

function (::ZZRing)(a::RealElem)
   return ZZRingElem(a)
end

@doc Markdown.doc"""
    setunion(x::RealElem, y::RealElem)

Return an `arb` containing the union of the intervals represented by $x$ and
$y$.
"""
function setunion(x::RealElem, y::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_union, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, x, y, prec)
  return z
end

@doc Markdown.doc"""
    setintersection(x::RealElem, y::RealElem)

Return an `arb` containing the intersection of the intervals represented by
$x$ and $y$.
"""
function setintersection(x::RealElem, y::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_intersection, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, x, y, prec)
  return z
end

################################################################################
#
#  Constants
#
################################################################################

@doc Markdown.doc"""
    const_pi(r::RealField)

Return $\pi = 3.14159\ldots$ as an element of $r$.
"""
function const_pi(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_pi, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

@doc Markdown.doc"""
    const_e(r::RealField)

Return $e = 2.71828\ldots$ as an element of $r$.
"""
function const_e(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_e, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

@doc Markdown.doc"""
    const_log2(r::RealField)

Return $\log(2) = 0.69314\ldots$ as an element of $r$.
"""
function const_log2(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_log2, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

@doc Markdown.doc"""
    const_log10(r::RealField)

Return $\log(10) = 2.302585\ldots$ as an element of $r$.
"""
function const_log10(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_log10, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

@doc Markdown.doc"""
    const_euler(r::RealField)

Return Euler's constant $\gamma = 0.577215\ldots$ as an element of $r$.
"""
function const_euler(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_euler, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

@doc Markdown.doc"""
    const_catalan(r::RealField)

Return Catalan's constant $C = 0.915965\ldots$ as an element of $r$.
"""
function const_catalan(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_catalan, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

@doc Markdown.doc"""
    const_khinchin(r::RealField)

Return Khinchin's constant $K = 2.685452\ldots$ as an element of $r$.
"""
function const_khinchin(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_khinchin, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

@doc Markdown.doc"""
    const_glaisher(r::RealField)

Return Glaisher's constant $A = 1.282427\ldots$ as an element of $r$.
"""
function const_glaisher(r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_const_glaisher, libarb), Nothing, (Ref{RealElem}, Int), z, prec)
  return z
end

################################################################################
#
#  Real valued functions
#
################################################################################

# real - real functions

function floor(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_floor, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

floor(::Type{RealElem}, x::RealElem) = floor(x)
floor(::Type{ZZRingElem}, x::RealElem) = ZZRingElem(floor(x))
floor(::Type{T}, x::RealElem) where {T <: Integer} = T(floor(x))

function ceil(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_ceil, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

ceil(::Type{RealElem}, x::RealElem) = ceil(x)
ceil(::Type{ZZRingElem}, x::RealElem) = ZZRingElem(ceil(x))
ceil(::Type{T}, x::RealElem) where {T <: Integer} = T(ceil(x))

function Base.sqrt(x::RealElem, prec = precision(Balls); check::Bool=true)
   z = RealElem()
   ccall((:arb_sqrt, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    rsqrt(x::RealElem)

Return the reciprocal of the square root of $x$, i.e. $1/\sqrt{x}$.
"""
function rsqrt(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_rsqrt, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    sqrt1pm1(x::RealElem)

Return $\sqrt{1+x}-1$, evaluated accurately for small $x$.
"""
function sqrt1pm1(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_sqrt1pm1, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    sqrtpos(x::RealElem)

Return the sqrt root of $x$, assuming that $x$ represents a nonnegative
number. Thus any negative number in the input interval is discarded.
"""
function sqrtpos(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_sqrtpos, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function log(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_log, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function log1p(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_log1p, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function Base.exp(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_exp, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function expm1(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_expm1, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function sin(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_sin, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function cos(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_cos, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function sinpi(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_sin_pi, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function cospi(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_cos_pi, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function tan(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_tan, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function cot(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_cot, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function tanpi(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_tan_pi, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function cotpi(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_cot_pi, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function sinh(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_sinh, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function cosh(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_cosh, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function tanh(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_tanh, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function coth(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_coth, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function atan(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_atan, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function asin(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_asin, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function acos(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_acos, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function atanh(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_atanh, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function asinh(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_asinh, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function acosh(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_acosh, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    gamma(x::RealElem)

Return the Gamma function evaluated at $x$.
"""
function gamma(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_gamma, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    lgamma(x::RealElem)

Return the logarithm of the Gamma function evaluated at $x$.
"""
function lgamma(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_lgamma, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    rgamma(x::RealElem)

Return the reciprocal of the Gamma function evaluated at $x$.
"""
function rgamma(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_rgamma, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    digamma(x::RealElem)

Return the  logarithmic derivative of the gamma function evaluated at $x$,
i.e. $\psi(x)$.
"""
function digamma(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_digamma, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

@doc Markdown.doc"""
    gamma(s::RealElem, x::RealElem)

Return the upper incomplete gamma function $\Gamma(s,x)$.
"""
function gamma(s::RealElem, x::RealElem, prec = precision(Balls))
  z = parent(s)()
  ccall((:arb_hypgeom_gamma_upper, libarb), Nothing,
        (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int, Int), z, s, x, 0, prec)
  return z
end

@doc Markdown.doc"""
    gamma_regularized(s::RealElem, x::RealElem)

Return the regularized upper incomplete gamma function
$\Gamma(s,x) / \Gamma(s)$.
"""
function gamma_regularized(s::RealElem, x::RealElem, prec = precision(Balls))
  z = parent(s)()
  ccall((:arb_hypgeom_gamma_upper, libarb), Nothing,
        (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int, Int), z, s, x, 1, prec)
  return z
end

@doc Markdown.doc"""
    gamma_lower(s::RealElem, x::RealElem)

Return the lower incomplete gamma function $\gamma(s,x) / \Gamma(s)$.
"""
function gamma_lower(s::RealElem, x::RealElem, prec = precision(Balls))
  z = parent(s)()
  ccall((:arb_hypgeom_gamma_lower, libarb), Nothing,
        (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int, Int), z, s, x, 0, prec)
  return z
end

@doc Markdown.doc"""
    gamma_lower_regularized(s::RealElem, x::RealElem)

Return the regularized lower incomplete gamma function
$\gamma(s,x) / \Gamma(s)$.
"""
function gamma_lower_regularized(s::RealElem, x::RealElem, prec = precision(Balls))
  z = parent(s)()
  ccall((:arb_hypgeom_gamma_lower, libarb), Nothing,
        (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int, Int), z, s, x, 1, prec)
  return z
end


@doc Markdown.doc"""
    zeta(x::RealElem)

Return the Riemann zeta function evaluated at $x$.
"""
function zeta(x::RealElem, prec = precision(Balls))
   z = RealElem()
   ccall((:arb_zeta, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Int), z, x, prec)
   return z
end

function sincos(x::RealElem, prec = precision(Balls))
  s = RealElem()
  c = RealElem()
  ccall((:arb_sin_cos, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), s, c, x, prec)
  return (s, c)
end

function sincospi(x::RealElem, prec = precision(Balls))
  s = RealElem()
  c = RealElem()
  ccall((:arb_sin_cos_pi, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), s, c, x, prec)
  return (s, c)
end

function sinpi(x::QQFieldElem, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_sin_pi_fmpq, libarb), Nothing,
        (Ref{RealElem}, Ref{QQFieldElem}, Int), z, x, prec)
  return z
end

function cospi(x::QQFieldElem, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_cos_pi_fmpq, libarb), Nothing,
        (Ref{RealElem}, Ref{QQFieldElem}, Int), z, x, prec)
  return z
end

function sincospi(x::QQFieldElem, r::RealField, prec = precision(Balls))
  s = r()
  c = r()
  ccall((:arb_sin_cos_pi_fmpq, libarb), Nothing,
        (Ref{RealElem}, Ref{RealElem}, Ref{QQFieldElem}, Int), s, c, x, prec)
  return (s, c)
end

function sinhcosh(x::RealElem, prec = precision(Balls))
  s = RealElem()
  c = RealElem()
  ccall((:arb_sinh_cosh, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), s, c, x, prec)
  return (s, c)
end

function atan(y::RealElem, x::RealElem, prec = precision(Balls))
  z = parent(y)()
  ccall((:arb_atan2, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, y, x, prec)
  return z
end

@doc Markdown.doc"""
    atan2(y::RealElem, x::RealElem)

Return $\operatorname{atan2}(y,x) = \arg(x+yi)$. Same as `atan(y, x)`.
"""
function atan2(y::RealElem, x::RealElem, prec = precision(Balls))
  return atan(y, x, prec)
end

@doc Markdown.doc"""
    agm(x::RealElem, y::RealElem)

Return the arithmetic-geometric mean of $x$ and $y$
"""
function agm(x::RealElem, y::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_agm, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, x, y, prec)
  return z
end

@doc Markdown.doc"""
    zeta(s::RealElem, a::RealElem)

Return the Hurwitz zeta function $\zeta(s,a)$.
"""
function zeta(s::RealElem, a::RealElem, prec = precision(Balls))
  z = parent(s)()
  ccall((:arb_hurwitz_zeta, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, s, a, prec)
  return z
end

function hypot(x::RealElem, y::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_hypot, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, x, y, prec)
  return z
end

function root(x::RealElem, n::UInt, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_root, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Int), z, x, n, prec)
  return z
end

@doc Markdown.doc"""
    root(x::RealElem, n::Int)

Return the $n$-th root of $x$. We require $x \geq 0$.
"""
function root(x::RealElem, n::Int, prec = precision(Balls))
  x < 0 && throw(DomainError(x, "Argument must be positive"))
  return root(x, UInt(n))
end

@doc Markdown.doc"""
    factorial(x::RealElem)

Return the factorial of $x$.
"""
factorial(x::RealElem, prec = precision(Balls)) = gamma(x+1)

function factorial(n::UInt, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_fac_ui, libarb), Nothing, (Ref{RealElem}, UInt, Int), z, n, prec)
  return z
end

@doc Markdown.doc"""
    factorial(n::Int, r::RealField)

Return the factorial of $n$ in the given Arb field.
"""
factorial(n::Int, r::RealField, prec = precision(Balls)) = n < 0 ? factorial(r(n), prec) : factorial(UInt(n), r, prec)

@doc Markdown.doc"""
    binomial(x::RealElem, n::UInt)

Return the binomial coefficient ${x \choose n}$.
"""
function binomial(x::RealElem, n::UInt, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_bin_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Int), z, x, n, prec)
  return z
end

@doc Markdown.doc"""
    binomial(n::UInt, k::UInt, r::RealField)

Return the binomial coefficient ${n \choose k}$ in the given Arb field.
"""
function binomial(n::UInt, k::UInt, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_bin_uiui, libarb), Nothing,
              (Ref{RealElem}, UInt, UInt, Int), z, n, k, prec)
  return z
end

@doc Markdown.doc"""
    fibonacci(n::ZZRingElem, r::RealField)

Return the $n$-th Fibonacci number in the given Arb field.
"""
function fibonacci(n::ZZRingElem, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_fib_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{ZZRingElem}, Int), z, n, prec)
  return z
end

function fibonacci(n::UInt, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_fib_ui, libarb), Nothing,
              (Ref{RealElem}, UInt, Int), z, n, prec)
  return z
end

@doc Markdown.doc"""
    fibonacci(n::Int, r::RealField)

Return the $n$-th Fibonacci number in the given Arb field.
"""
fibonacci(n::Int, r::RealField, prec = precision(Balls)) = n >= 0 ? fibonacci(UInt(n), r, prec) : fibonacci(ZZRingElem(n), r, prec)

@doc Markdown.doc"""
    gamma(x::ZZRingElem, r::RealField)

Return the Gamma function evaluated at $x$ in the given Arb field.
"""
function gamma(x::ZZRingElem, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_gamma_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{ZZRingElem}, Int), z, x, prec)
  return z
end

@doc Markdown.doc"""
    gamma(x::QQFieldElem, r::RealField)

Return the Gamma function evaluated at $x$ in the given Arb field.
"""
function gamma(x::QQFieldElem, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_gamma_fmpq, libarb), Nothing,
              (Ref{RealElem}, Ref{QQFieldElem}, Int), z, x, prec)
  return z
end


function zeta(n::UInt, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_zeta_ui, libarb), Nothing,
              (Ref{RealElem}, UInt, Int), z, n, prec)
  return z
end

@doc Markdown.doc"""
    zeta(n::Int, r::RealField)

Return the Riemann zeta function $\zeta(n)$ as an element of the given Arb
field.
"""
zeta(n::Int, r::RealField, prec = precision(Balls)) = n >= 0 ? zeta(UInt(n), r, prec) : zeta(r(n), prec)

function bernoulli(n::UInt, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_bernoulli_ui, libarb), Nothing,
              (Ref{RealElem}, UInt, Int), z, n, prec)
  return z
end

@doc Markdown.doc"""
    bernoulli(n::Int, r::RealField)

Return the $n$-th Bernoulli number as an element of the given Arb field.
"""
bernoulli(n::Int, r::RealField, prec = precision(Balls)) = n >= 0 ? bernoulli(UInt(n), r, prec) : throw(DomainError(n, "Index must be non-negative"))

function rising_factorial(x::RealElem, n::UInt, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_rising_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Int), z, x, n, prec)
  return z
end

@doc Markdown.doc"""
    rising_factorial(x::RealElem, n::Int)

Return the rising factorial $x(x + 1)\ldots (x + n - 1)$ as an Arb.
"""
rising_factorial(x::RealElem, n::Int, prec = precision(Balls)) = n < 0 ? throw(DomainError(n, "Index must be non-negative")) : rising_factorial(x, UInt(n), prec)

function rising_factorial(x::QQFieldElem, n::UInt, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_rising_fmpq_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{QQFieldElem}, UInt, Int), z, x, n, prec)
  return z
end

@doc Markdown.doc"""
    rising_factorial(x::QQFieldElem, n::Int, r::RealField)

Return the rising factorial $x(x + 1)\ldots (x + n - 1)$ as an element of the
given Arb field.
"""
rising_factorial(x::QQFieldElem, n::Int, r::RealField, prec = precision(Balls)) = n < 0 ? throw(DomainError(n, "Index must be non-negative")) : rising_factorial(x, UInt(n), r, prec)

function rising_factorial2(x::RealElem, n::UInt, prec = precision(Balls))
  z = RealElem()
  w = RealElem()
  ccall((:arb_rising2_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, UInt, Int), z, w, x, n, prec)
  return (z, w)
end

@doc Markdown.doc"""
    rising_factorial2(x::RealElem, n::Int)

Return a tuple containing the rising factorial $x(x + 1)\ldots (x + n - 1)$
and its derivative.
"""
rising_factorial2(x::RealElem, n::Int, prec = precision(Balls)) = n < 0 ? throw(DomainError(n, "Index must be non-negative")) : rising_factorial2(x, UInt(n), prec)

function polylog(s::RealElem, a::RealElem, prec = precision(Balls))
  z = parent(s)()
  ccall((:arb_polylog, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int), z, s, a, prec)
  return z
end

function polylog(s::Int, a::RealElem, prec = precision(Balls))
  z = parent(a)()
  ccall((:arb_polylog_si, libarb), Nothing,
              (Ref{RealElem}, Int, Ref{RealElem}, Int), z, s, a, prec)
  return z
end

@doc Markdown.doc"""
    polylog(s::Union{RealElem,Int}, a::RealElem)

Return the polylogarithm Li$_s(a)$.
""" polylog(s::Union{RealElem,Int}, a::RealElem)

function chebyshev_t(n::UInt, x::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_chebyshev_t_ui, libarb), Nothing,
              (Ref{RealElem}, UInt, Ref{RealElem}, Int), z, n, x, prec)
  return z
end

function chebyshev_u(n::UInt, x::RealElem, prec = precision(Balls))
  z = RealElem()
  ccall((:arb_chebyshev_u_ui, libarb), Nothing,
              (Ref{RealElem}, UInt, Ref{RealElem}, Int), z, n, x, prec)
  return z
end

function chebyshev_t2(n::UInt, x::RealElem, prec = precision(Balls))
  z = RealElem()
  w = RealElem()
  ccall((:arb_chebyshev_t2_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Ref{RealElem}, Int), z, w, n, x, prec)
  return z, w
end

function chebyshev_u2(n::UInt, x::RealElem, prec = precision(Balls))
  z = RealElem()
  w = RealElem()
  ccall((:arb_chebyshev_u2_ui, libarb), Nothing,
              (Ref{RealElem}, Ref{RealElem}, UInt, Ref{RealElem}, Int), z, w, n, x, prec)
  return z, w
end

@doc Markdown.doc"""
    chebyshev_t(n::Int, x::RealElem)

Return the value of the Chebyshev polynomial $T_n(x)$.
"""
chebyshev_t(n::Int, x::RealElem, prec = precision(Balls)) = n < 0 ? throw(DomainError(n, "Index must be non-negative")) : chebyshev_t(UInt(n), x, prec)

@doc Markdown.doc"""
    chebyshev_u(n::Int, x::RealElem)

Return the value of the Chebyshev polynomial $U_n(x)$.
"""
chebyshev_u(n::Int, x::RealElem, prec = precision(Balls)) = n < 0 ? throw(DomainError(n, "Index must be non-negative")) : chebyshev_u(UInt(n), x, prec)

@doc Markdown.doc"""
    chebyshev_t2(n::Int, x::RealElem)

Return the tuple $(T_{n}(x), T_{n-1}(x))$.
"""
chebyshev_t2(n::Int, x::RealElem, prec = precision(Balls)) = n < 0 ? throw(DomainError(n, "Index must be non-negative")) : chebyshev_t2(UInt(n), x, prec)

@doc Markdown.doc"""
    chebyshev_u2(n::Int, x::RealElem)

Return the tuple $(U_{n}(x), U_{n-1}(x))$
"""
chebyshev_u2(n::Int, x::RealElem, prec = precision(Balls)) = n < 0 ? throw(DomainError(n, "Index must be non-negative")) : chebyshev_u2(UInt(n), x, prec)

@doc Markdown.doc"""
    bell(n::ZZRingElem, r::RealField)

Return the Bell number $B_n$ as an element of $r$.
"""
function bell(n::ZZRingElem, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_bell_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{ZZRingElem}, Int), z, n, prec)
  return z
end

@doc Markdown.doc"""
    bell(n::Int, r::RealField)

Return the Bell number $B_n$ as an element of $r$.
"""
bell(n::Int, r::RealField, prec = precision(Balls)) = bell(ZZRingElem(n), r, prec)

@doc Markdown.doc"""
    numpart(n::ZZRingElem, r::RealField)

Return the number of partitions $p(n)$ as an element of $r$.
"""
function numpart(n::ZZRingElem, r::RealField, prec = precision(Balls))
  z = r()
  ccall((:arb_partitions_fmpz, libarb), Nothing,
              (Ref{RealElem}, Ref{ZZRingElem}, Int), z, n, prec)
  return z
end

@doc Markdown.doc"""
    numpart(n::Int, r::RealField)

Return the number of partitions $p(n)$ as an element of $r$.
"""
numpart(n::Int, r::RealField, prec = precision(Balls)) = numpart(ZZRingElem(n), r, prec)

################################################################################
#
#  Hypergeometric and related functions
#
################################################################################

@doc Markdown.doc"""
    airy_ai(x::RealElem)

Return the Airy function $\operatorname{Ai}(x)$.
"""
function airy_ai(x::RealElem, prec = precision(Balls))
  ai = RealElem()
  ccall((:arb_hypgeom_airy, libarb), Nothing,
              (Ref{RealElem}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{RealElem}, Int),
              ai, C_NULL, C_NULL, C_NULL, x, prec)
  return ai
end

@doc Markdown.doc"""
    airy_bi(x::RealElem)

Return the Airy function $\operatorname{Bi}(x)$.
"""
function airy_bi(x::RealElem, prec = precision(Balls))
  bi = RealElem()
  ccall((:arb_hypgeom_airy, libarb), Nothing,
              (Ptr{Cvoid}, Ptr{Cvoid}, Ref{RealElem}, Ptr{Cvoid}, Ref{RealElem}, Int),
              C_NULL, C_NULL, bi, C_NULL, x, prec)
  return bi
end

@doc Markdown.doc"""
    airy_ai_prime(x::RealElem)

Return the derivative of the Airy function $\operatorname{Ai}^\prime(x)$.
"""
function airy_ai_prime(x::RealElem, prec = precision(Balls))
  ai_prime = RealElem()
  ccall((:arb_hypgeom_airy, libarb), Nothing,
              (Ptr{Cvoid}, Ref{RealElem}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{RealElem}, Int),
              C_NULL, ai_prime, C_NULL, C_NULL, x, prec)
  return ai_prime
end

@doc Markdown.doc"""
    airy_bi_prime(x::RealElem)

Return the derivative of the Airy function $\operatorname{Bi}^\prime(x)$.
"""
function airy_bi_prime(x::RealElem, prec = precision(Balls))
  bi_prime = RealElem()
  ccall((:arb_hypgeom_airy, libarb), Nothing,
              (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{RealElem}, Ref{RealElem}, Int),
              C_NULL, C_NULL, C_NULL, bi_prime, x, prec)
  return bi_prime
end

################################################################################
#
#  Linear dependence
#
################################################################################

@doc Markdown.doc"""
    lindep(A::Vector{RealElem}, bits::Int)

Find a small linear combination of the entries of the array $A$ that is small
(using LLL). The entries are first scaled by the given number of bits before
truncating to integers for use in LLL. This function can be used to find linear
dependence between a list of real numbers. The algorithm is heuristic only and
returns an array of Nemo integers representing the linear combination.
"""
function lindep(A::Vector{RealElem}, bits::Int)
  bits < 0 && throw(DomainError(bits, "Number of bits must be non-negative"))
  n = length(A)
  V = [floor(ldexp(s, bits) + 0.5) for s in A]
  M = zero_matrix(ZZ, n, n + 1)
  for i = 1:n
    M[i, i] = ZZ(1)
    flag, M[i, n + 1] = unique_integer(V[i])
    !flag && error("Insufficient precision in lindep")
  end
  L = lll(M)
  return [L[1, i] for i = 1:n]
end

################################################################################
#
#  Simplest rational inside
#
################################################################################

@doc Markdown.doc"""
      simplest_rational_inside(x::RealElem)

Return the simplest fraction inside the ball $x$. A canonical fraction
$a_1/b_1$ is defined to be simpler than $a_2/b_2$ iff $b_1 < b_2$ or $b_1 =
b_2$ and $a_1 < a_2$.
"""
function simplest_rational_inside(x::RealElem)
   a = ZZRingElem()
   b = ZZRingElem()
   e = ZZRingElem()

   ccall((:arb_get_interval_fmpz_2exp, libarb), Nothing,
         (Ref{ZZRingElem}, Ref{ZZRingElem}, Ref{ZZRingElem}, Ref{RealElem}), a, b, e, x)
   !fits(Int, e) && error("Result does not fit into an QQFieldElem")
   _e = Int(e)
   if e >= 0
      return a << _e
   end
   _e = -_e
   d = ZZRingElem(1) << _e
   return _fmpq_simplest_between(a, d, b, d)
end

################################################################################
#
#  Unsafe operations
#
################################################################################

function zero!(z::RealElem)
   ccall((:arb_zero, libarb), Nothing, (Ref{RealElem},), z)
   return z
end

for (s,f) in (("add!","arb_add"), ("mul!","arb_mul"), ("div!", "arb_div"),
              ("sub!","arb_sub"))
  @eval begin
    function ($(Symbol(s)))(z::RealElem, x::RealElem, y::RealElem, prec = precision(Balls))
      ccall(($f, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int),
                           z, x, y, prec)
      return z
    end
  end
end

function addeq!(z::RealElem, x::RealElem, prec = precision(Balls))
    ccall((:arb_add, libarb), Nothing, (Ref{RealElem}, Ref{RealElem}, Ref{RealElem}, Int),
                           z, z, x, prec)
    return z
end

################################################################################
#
#  Unsafe setting
#
################################################################################

for (typeofx, passtoc) in ((RealElem, Ref{RealElem}), (Ptr{RealElem}, Ptr{RealElem}))
  for (f,t) in (("arb_set_si", Int), ("arb_set_ui", UInt),
                ("arb_set_d", Float64))
    @eval begin
      function _arb_set(x::($typeofx), y::($t))
        ccall(($f, libarb), Nothing, (($passtoc), ($t)), x, y)
      end

      function _arb_set(x::($typeofx), y::($t), p::Int)
        _arb_set(x, y)
        ccall((:arb_set_round, libarb), Nothing,
                    (($passtoc), ($passtoc), Int), x, x, p)
      end
    end
  end

  @eval begin
    function _arb_set(x::($typeofx), y::ZZRingElem)
      ccall((:arb_set_fmpz, libarb), Nothing, (($passtoc), Ref{ZZRingElem}), x, y)
    end

    function _arb_set(x::($typeofx), y::ZZRingElem, p::Int)
      ccall((:arb_set_round_fmpz, libarb), Nothing,
                  (($passtoc), Ref{ZZRingElem}, Int), x, y, p)
    end

    function _arb_set(x::($typeofx), y::QQFieldElem, p::Int)
      ccall((:arb_set_fmpq, libarb), Nothing,
                  (($passtoc), Ref{QQFieldElem}, Int), x, y, p)
    end

    function _arb_set(x::($typeofx), y::RealElem)
      ccall((:arb_set, libarb), Nothing, (($passtoc), Ref{RealElem}), x, y)
    end

    function _arb_set(x::($typeofx), y::RealElem, p::Int)
      ccall((:arb_set_round, libarb), Nothing,
                  (($passtoc), Ref{RealElem}, Int), x, y, p)
    end

    function _arb_set(x::($typeofx), y::AbstractString, p::Int)
      s = string(y)
      err = ccall((:arb_set_str, libarb), Int32,
                  (($passtoc), Ptr{UInt8}, Int), x, s, p)
      err == 0 || error("Invalid real string: $(repr(s))")
    end

    function _arb_set(x::($typeofx), y::BigFloat)
      m = ccall((:arb_mid_ptr, libarb), Ptr{arf_struct},
                  (($passtoc), ), x)
      r = ccall((:arb_rad_ptr, libarb), Ptr{mag_struct},
                  (($passtoc), ), x)
      ccall((:arf_set_mpfr, libarb), Nothing,
                  (Ptr{arf_struct}, Ref{BigFloat}), m, y)
      ccall((:mag_zero, libarb), Nothing, (Ptr{mag_struct}, ), r)
    end

    function _arb_set(x::($typeofx), y::BigFloat, p::Int)
      m = ccall((:arb_mid_ptr, libarb), Ptr{arf_struct}, (($passtoc), ), x)
      r = ccall((:arb_rad_ptr, libarb), Ptr{mag_struct}, (($passtoc), ), x)
      ccall((:arf_set_mpfr, libarb), Nothing,
                  (Ptr{arf_struct}, Ref{BigFloat}), m, y)
      ccall((:mag_zero, libarb), Nothing, (Ptr{mag_struct}, ), r)
      ccall((:arb_set_round, libarb), Nothing,
                  (($passtoc), ($passtoc), Int), x, x, p)
    end
  end
end

################################################################################
#
#  Parent object overloading
#
################################################################################

function (r::RealField)()
  z = RealElem()
  return z
end

function (r::RealField)(x::Int, prec = precision(Balls))
  z = RealElem(ZZRingElem(x), prec)
  return z
end

function (r::RealField)(x::UInt, prec = precision(Balls))
  z = RealElem(ZZRingElem(x), prec)
  return z
end

function (r::RealField)(x::ZZRingElem, prec = precision(Balls))
  z = RealElem(x, prec)
  return z
end

(r::RealField)(x::Integer, prec = precision(Balls)) = r(ZZRingElem(x), prec)

function (r::RealField)(x::QQFieldElem, prec = precision(Balls))
  z = RealElem(x, prec)
  return z
end

(r::RealField)(x::Rational{T}, prec = precision(Balls)) where {T <: Integer} = r(QQFieldElem(x), prec)

function (r::RealField)(x::Float64, prec = precision(Balls))
  z = RealElem(x, prec)
  return z
end

function (r::RealField)(x::RealElem, prec = precision(Balls))
  z = RealElem(x, prec)
  return z
end

function (r::RealField)(x::AbstractString, prec = precision(Balls))
  z = RealElem(x, prec)
  return z
end

function (r::RealField)(x::Irrational, prec = precision(Balls))
  if x == pi
    return const_pi(r)
  elseif x == e
    return const_e(precision(Balls))
  else
    error("constant not supported")
  end
end

function (r::RealField)(x::BigFloat, prec = precision(Balls))
  z = RealElem(x, prec)
  return z
end

################################################################################
#
#  Arb real field constructor
#
################################################################################

# see inner constructor for RealField

################################################################################
#
#  Random generation
#
################################################################################

@doc Markdown.doc"""
    rand(r::RealField; randtype::Symbol=:urandom)

Return a random element in given Arb field.

The `randtype` default is `:urandom` which return an `arb` contained in
$[0,1]$.

The rest of the methods return non-uniformly distributed values in order to
exercise corner cases. The option `:randtest` will return a finite number, and
`:randtest_exact` the same but with a zero radius. The option
`:randtest_precise` return an `arb` with a radius around $2^{-\mathrm{prec}}$
the magnitude of the midpoint, while `:randtest_wide` return a radius that
might be big relative to its midpoint. The `:randtest_special`-option might
return a midpoint and radius whose values are `NaN` or `inf`.
"""
function rand(r::RealField, prec = precision(Balls); randtype::Symbol=:urandom)
  state = _flint_rand_states[Threads.threadid()]
  x = r()

  if randtype == :urandom
    ccall((:arb_urandom, libarb), Nothing,
          (Ref{RealElem}, Ptr{Cvoid}, Int), x, state.ptr, prec)
  elseif randtype == :randtest
    ccall((:arb_randtest, libarb), Nothing,
          (Ref{RealElem}, Ptr{Cvoid}, Int, Int), x, state.ptr, prec, 30)
  elseif randtype == :randtest_exact
    ccall((:arb_randtest_exact, libarb), Nothing,
          (Ref{RealElem}, Ptr{Cvoid}, Int, Int), x, state.ptr, prec, 30)
  elseif randtype == :randtest_precise
    ccall((:arb_randtest_precise, libarb), Nothing,
          (Ref{RealElem}, Ptr{Cvoid}, Int, Int), x, state.ptr, prec, 30)
  elseif randtype == :randtest_wide
    ccall((:arb_randtest_wide, libarb), Nothing,
          (Ref{RealElem}, Ptr{Cvoid}, Int, Int), x, state.ptr, prec, 30)
  elseif randtype == :randtest_special
    ccall((:arb_randtest_special, libarb), Nothing,
          (Ref{RealElem}, Ptr{Cvoid}, Int, Int), x, state.ptr, prec, 30)
  else
    error("Arb random generation `" * String(randtype) * "` is not defined")
  end

  return x
end