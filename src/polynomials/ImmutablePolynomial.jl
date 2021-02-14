export ImmutablePolynomial

"""
    ImmutablePolynomial{T<:Number, X, N}(coeffs::AbstractVector{T})

Construct an immutable (static) polynomial from its coefficients 
`a₀, a₁, …, aₙ`,
lowest order first, optionally in terms of the given variable `x`
where `x` can be a character, symbol, or string.

If ``p = a_n x^n + \\ldots + a_2 x^2 + a_1 x + a_0``, we construct
this through `ImmutablePolynomial((a_0, a_1, ..., a_n))` (assuming
`a_n ≠ 0`). As well, a vector or number can be used for construction.


The usual arithmetic operators are overloaded to work with polynomials
as well as with combinations of polynomials and scalars. However,
operations involving two non-constant polynomials of different variables causes an
error. Unlike other polynomials, `setindex!` is not defined for `ImmutablePolynomials`.

As the coefficient size is a compile-time constant, several performance
improvements are possible. For example, immutable polynomials can take advantage of 
faster polynomial evaluation provided by `evalpoly` from Julia 1.4.

!!! note
    `ImmutablePolynomial` is not axis-aware, and it treats `coeffs` simply as a list of coefficients with the first 
    index always corresponding to the constant term.

# Examples

```jldoctest
julia> using  Polynomials

julia> ImmutablePolynomial((1, 0, 3, 4))
ImmutablePolynomial(1 + 3*x^2 + 4*x^3)

julia> ImmutablePolynomial((1, 2, 3), :s)
ImmutablePolynomial(1 + 2*s + 3*s^2)

julia> one(ImmutablePolynomial)
ImmutablePolynomial(1.0)
```

!!! note
    This was modeled after https://github.com/tkoolen/StaticUnivariatePolynomials.jl by @tkoolen.

"""
struct ImmutablePolynomial{T <: Number, X, N} <: StandardBasisPolynomial{T, X}
    coeffs::NTuple{N, T}
    function ImmutablePolynomial{T,X,N}(coeffs::NTuple{N,T}) where {T <: Number, X, N}
        N == 0 && return new{T,X, 0}(coeffs)
        iszero(coeffs[end]) &&  throw(ArgumentError("Leading  term must  be  non-zero"))
        new{T,X,N}(coeffs)
    end
end

@register ImmutablePolynomial

## Various interfaces

## Abstract Vector coefficients
function ImmutablePolynomial{T,X}(coeffs::AbstractVector{S})  where {T,X,S}
    R = promote_type(T,S)
    
    if Base.has_offset_axes(coeffs)
        @warn "ignoring the axis offset of the coefficient vector"
    end
    N = findlast(!iszero, coeffs)
    isnothing(N) && return ImmutablePolynomial{R,X,0}(())
    N′ = N + 1 - firstindex(coeffs)
    cs = NTuple{N′,T}(coeffs[i] for i ∈ firstindex(coeffs):N)
    ImmutablePolynomial{T, X, N′}(cs)
end

## -- Tuple arguments
function ImmutablePolynomial{T,X}(coeffs::Tuple)  where {T,X}
    N = findlast(!iszero, coeffs)
    isnothing(N) && return zero(ImmutablePolynomial{T,X})
    ImmutablePolynomial{T,X,N}(NTuple{N,T}(coeffs[i] for i in 1:N))
end

ImmutablePolynomial{T}(coeffs::Tuple, var::SymbolLike=:x)  where {T} = ImmutablePolynomial{T,Symbol(var)}(coeffs)

function ImmutablePolynomial(coeffs::Tuple, var::SymbolLike=:x)
    cs = NTuple(promote(coeffs...))
    T = eltype(cs)
    ImmutablePolynomial{T, Symbol(var)}(cs)
end


##
## ----
##
# overrides from common.jl due to  coeffs being non mutable, N in type parameters
Base.collect(p::P) where {P <: ImmutablePolynomial} = [pᵢ for pᵢ ∈ p]

Base.copy(p::P) where {P <: ImmutablePolynomial} = P(coeffs(p))

## defining these speeds things up
function Base.zero(P::Type{<:ImmutablePolynomial}, var::SymbolLike=indeterminate(P))
    R = eltype(P)
    ImmutablePolynomial{R,Symbol(var),0}(NTuple{0,R}())
end

function  Base.one(P::Type{<:ImmutablePolynomial}, var::SymbolLike=indeterminate(P))
    R = eltype(P)
    ImmutablePolynomial{R,Symbol(var),1}(NTuple{1,R}(one(R)))
end
function variable(P::Type{<:ImmutablePolynomial}, var::SymbolLike=indeterminate(P))
    R  = eltype(P)
    ImmutablePolynomial{R,Symbol(var),2}(NTuple{2,R}((zero(R), one(R))))
end


# degree, isconstant
degree(p::ImmutablePolynomial{T,X, N}) where {T,X,N} = N - 1 # no trailing zeros
isconstant(p::ImmutablePolynomial{T,X,N}) where {T,X,N}  = N <= 1

function Base.getindex(p::ImmutablePolynomial{T,X, N}, idx::Int) where {T <: Number,X, N}
    (idx <  0 || idx > N-1) && return zero(T)
    return p.coeffs[idx + 1]
end

Base.setindex!(p::ImmutablePolynomial, val::Number,  idx::Int) = throw(ArgumentError("ImmutablePolynomials are immutable"))

for op in [:isequal, :(==)]
    @eval function Base.$op(p1::ImmutablePolynomial{T,N}, p2::ImmutablePolynomial{S,M}) where {T,N,S,M}
        check_same_variable(p1,p2) || return false
        p1s, p2s = coeffs(p1), coeffs(p2)
        (N == M  && $op(p1s,p2s)) &&  return  true
        n1 = findlast(!iszero, p1s) # now trim out zeros
        n2 = findlast(!iszero, p2s)
        (n1 == nothing && n2 == nothing) && return true
        (n1 == nothing || n2  == nothing) && return false
        $op(p1s[1:n1],p2s[1:n2]) &&  return true 
        false
    end
end

# in common.jl these call chop! and truncate!
function Base.chop(p::ImmutablePolynomial{T,X,N};
              rtol::Real = Base.rtoldefault(real(T)),
              atol::Real = 0)  where {T,X,N}
    cs = coeffs(p)
    for i in N:-1:1
        if !isapprox(cs[i], zero(T), rtol=rtol, atol=atol)
            return ImmutablePolynomial{T,X,i}(cs[1:i])
        end
    end
    zero(ImmutablePolynomial{T,X})
end

function Base.truncate(p::ImmutablePolynomial{T,X,N};
                       rtol::Real = Base.rtoldefault(real(T)),
                       atol::Real = 0)  where {T,X,N}
    q = chop(p, rtol=rtol, atol=atol)
    iszero(q) && return  q
    cs = coeffs(q)
    thresh = maximum(abs,cs) * rtol + atol
    cs′ = map(c->abs(c) <= thresh ? zero(T) : c, cs)
    ImmutablePolynomial{T,X}(tuple(cs′...))
end

# no in-place chop! and truncate!
chop!(p::ImmutablePolynomial; kwargs...) =  chop(p; kwargs...)
truncate!(p::ImmutablePolynomial; kwargs...) =  truncate(p; kwargs...)

##
## --------------------
##

(p::ImmutablePolynomial{T,X,N})(x::S) where {T,X,N,S} = evalpoly(x, p.coeffs)


function Base.:+(p1::ImmutablePolynomial{T,X,N}, p2::ImmutablePolynomial{S,Y,M}) where {T,X,N,S,Y,M}

    R = promote_type(S,T)
    iszero(N) && return ImmutablePolynomial{R,Y}(coeffs(p2))
    iszero(M) && return ImmutablePolynomial{R,X}(coeffs(p1))

    if X != Y
        isconstant(p1) && return ImmutablePolynomial{T,Y,1}(p1.coeffs) + p2 
        isconstant(p2) && return p1 + ImmutablePolynomial{S,X,1}(p2.coeffs)
        error("Polynomials must have same variable")
    end

    if  N == M
        cs = NTuple{N,R}(p1[i] + p2[i] for i in 0:N-1)
        ImmutablePolynomial{R,X}(cs)        
    elseif N < M
        cs = (p2.coeffs) ⊕ (p1.coeffs)
        ImmutablePolynomial{R,X,M}(convert(NTuple{M,R}, cs))
    else
        cs = (p1.coeffs) ⊕ (p2.coeffs)
        ImmutablePolynomial{R,X,N}(convert(NTuple{N,R}, cs))
    end

end

# not type stable!!!
function Base.:*(p1::ImmutablePolynomial{T,X,N}, p2::ImmutablePolynomial{S,Y,M}) where {T,X,N,S,Y,M}
    isconstant(p1) && return p2 * p1[0] 
    isconstant(p2) && return p1 * p2[0]
    X != Y && error("Polynomials must have same variable")
    R = promote_type(S,T)
    cs = (p1.coeffs) ⊗ (p2.coeffs)
    if !iszero(cs[end])
        return ImmutablePolynomial{R, X, N+M-1}(cs)
    else
        n = findlast(!iszero, cs)
        return ImmutablePolynomial{R, X, n}(NTuple{n,R}(cs[i] for i ∈ 1:n))
    end
end

# Padded vector sum of two tuples assuming N > M
# assume N > M.
# As N ≠ M, we are assured of size of output (max(N,M)), so we generate the function
@generated function ⊕(p1::NTuple{N,T}, p2::NTuple{M,S}) where {T,N,S,M}

    R = promote_type(T,S)

    exprs = Any[nothing for i = 1:N]
    for i in  1:M
        exprs[i] = :(p1[$i] + p2[$i])
    end
    for i in M+1:N
        exprs[i] =:(p1[$i])
    end

    return quote
        Base.@_inline_meta
        tuple($(exprs...))
    end

end



## Static size of product makes generated functions  a good choice
## from https://github.com/tkoolen/StaticUnivariatePolynomials.jl/blob/master/src/monomial_basis.jl
## convolution of two tuples
@generated function ⊗(p1::NTuple{N,T}, p2::NTuple{M,S}) where {T,N,S,M}
    P = M + N - 1
    R = promote_type(T,S)
    exprs = Any[nothing for i = 1 : P]
    for i in 1 : N
        for j in 1 : M
            k = i + j - 1
            if exprs[k] === nothing
                exprs[k] = :(p1[$i] * p2[$j])
            else
                exprs[k] = :(muladd(p1[$i], p2[$j], $(exprs[k])))
            end
        end
    end

    return quote
        Base.@_inline_meta
        tuple($(exprs...))        
    end

end

# scalar ops
function Base.:+(p::ImmutablePolynomial{T,X,N}, c::S) where {T, X, N, S<:Number}
    R = promote_type(T,S)

    iszero(c) && return ImmutablePolynomial{R,X,N}(convert(NTuple{N,R},p.coeffs))
    N == 0 && return ImmutablePolynomial{R,X,1}((c,))
    N == 1 && return ImmutablePolynomial((p[0]+c,), X)
    q = p + ImmutablePolynomial{S,X,1}((c,))
    return q
    
end

function Base.:*(p::ImmutablePolynomial{T,X,N}, c::S) where {T, X,N, S <: Number}
    R = eltype(one(T)*one(S))
    iszero(p[end]*c) && return ImmutablePolynomial{R,X}(p.coeffs .* c)
    ImmutablePolynomial{R,X,N}(p.coeffs .* c)
end

function Base.:/(p::ImmutablePolynomial{T,X,N}, c::S) where {T,X,N,S <: Number}
    R = eltype(one(T)/one(S))
    cs = p.coeffs ./ c
    iszero(cs[end])  && return ImmutablePolynomial{R,X}(cs)
    ImmutablePolynomial{R,X,N}(cs)
end

Base.:-(p::ImmutablePolynomial{T,X,N}) where {T,X,N} = ImmutablePolynomial{T,X,N}(.-p.coeffs)

Base.to_power_type(p::ImmutablePolynomial{T,X,N}) where {T,X,N} = p


## more performant versions borrowed from StaticArrays
## https://github.com/JuliaArrays/StaticArrays.jl/blob/master/src/linalg.jl
LinearAlgebra.norm(q::ImmutablePolynomial{T,X,0}) where {T,X} = zero(real(float(T)))
LinearAlgebra.norm(q::ImmutablePolynomial) = _norm(q.coeffs)
LinearAlgebra.norm(q::ImmutablePolynomial, p::Real) = _norm(q.coeffs, p)

@generated function _norm(a::NTuple{N,T}) where {T, N}

    expr = :(abs2(a[1]))
    for j = 2:N
        expr = :($expr + abs2(a[$j]))
    end
    
    return quote
        $(Expr(:meta, :inline))
        @inbounds return sqrt($expr)
    end
    
end

_norm_p0(x) = iszero(x) ? zero(x) : one(x)
@generated function _norm(a::NTuple{N,T}, p::Real) where {T, N}
    expr = :(abs(a[1])^p)
    for j = 2:N
        expr = :($expr + abs(a[$j])^p)
    end

    expr_p1 = :(abs(a[1]))
    for j = 2:N
        expr_p1 = :($expr_p1 + abs(a[$j]))
    end

    return quote
        $(Expr(:meta, :inline))
        if p == Inf
            return mapreduce(abs, max, a)
        elseif p == 1
            @inbounds return $expr_p1
        elseif p == 2
            return norm(a)
        elseif p == 0
            return mapreduce(_norm_p0, +, a)
        else
            @inbounds return ($expr)^(inv(p))
        end
    end

end


