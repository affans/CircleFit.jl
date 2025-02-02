module CircleFit
import StatsBase
import StatsBase: RegressionModel, residuals, coef, coefnames, dof
import Statistics: var, cov, stdm

export circfit, Circle, algorithm

"""
Circle fit model 

Currently only in 2D

* position: center position of the fitted circle
* radius: radius of the fitted circle
* points: the data to fit to. Points are stored as a matrix (number of points, number of dimensions)
* alg: algorithm to use. Possible options are :kasa, :pratt, :graf and :taubin

To get the coefficients one can use StatsBase.coef
The coeffient names are provived by StatsBase.coefnames
"""
struct Circle <: RegressionModel
    position::AbstractArray
    radius
    points::AbstractArray
    alg::Symbol
end

"""
Get the algorithm used in the fit
"""
algorithm(model::Circle) = model.alg

# StatsBase methods

StatsBase.coef(fit::Circle) = (fit.position..., fit.radius)
StatsBase.coefnames(fit::Circle) = (("center position x".*string.(1:length(fit.position)))..., "radius")
StatsBase.dof(fit::Circle) = size(fit.points,1) - length(coef(fit))
function StatsBase.residuals(fit::Circle)
    rs = @. hypot(fit.points[:,1] - fit.position[1], fit.points[:,2] - fit.position[2])
    rs .- fit.radius
end
StatsBase.rss(fit::Circle) = sum(abs2.(residuals(fit)))

function StatsBase.fit(::Type{Circle},x::AbstractArray,y::AbstractArray;alg=:kasa) 
    x0,y0,r = if alg == :taubin
        taubin(x,y)
    elseif alg == :pratt
        pratt(x,y)
    elseif alg == :graf
        p0 = collect(kasa(x,y))
        GRAF(x,y,p0)
    else
        kasa(x,y)
    end
    Circle([x0,y0],r,[x y],alg)
end

# Old method interface

"""
Fit a circle to points provided as arrays of x and y coordinates

Example
```
x = [-1.0,0,0,1]
y = [0.0,1,-1,0]
x0,y0,radius = circfit(x,y)
```
"""

@deprecate circfit(x::AbstractArray,y::AbstractArray) StatsBase.fit(Circle,x,y) true

"""
Fit a circle to the points provided as arrays of x and y coordinates

This method uses [Kåsa's method](https://doi.org/10.1109/TIM.1976.6312298)
The result is a GeometryBasics::Circle
"""
function kasa(x::AbstractArray, y::AbstractArray)
    x² = x.^2
    y² = y.^2
    
    A = var(x) 
    B = cov(x, y) 
    C = var(y) 
    D = cov(x, y²) + cov(x, x²)
    E = cov(y, x²) + cov(y, y²) 

    ACB2 = 2 * (A * C - B^2)
    am = (D * C - B * E) / ACB2 
    bm = (A * E - B * D) / ACB2
    rk = hypot(stdm(x, am, corrected=false), stdm(y, bm, corrected=false))

    (am, bm, rk)
end

using LinearAlgebra

"""
Fit a circle by using Taubin's method
https://doi.org/10.1007/s10851-005-0482-8
Warning: not optimized
"""
function taubin(x,y)

    z = x.^2 .+ y.^2
    Mx = sum(x)
    My = sum(y)
    Mz = sum(z)
    Mxx = sum(x.^2)
    Myx = Mxy = sum(x.*y)
    Mzx = Mxz = sum(x.*z)
    Myy = sum(y.^2)
    Mzy = Myz = sum(y.*z)
    Mzz = sum(z.^2)
    n = length(x)

    C = [4Mz 2Mx 2My 0
         2Mx n   0   0
         2My 0   n   0
         0   0   0   0]
        
    M = [Mzz Mxz Myz Mz
         Mxz Mxx Mxy Mx
         Myz Mxy Myy My
         Mz  Mx  My  n]

    F = eigen(M,C)

    values = F.values
    values[values .< 0] .= Inf
    i = argmin(values)

    A,B,C,D = F.vectors[:,i]

    a = -B/(2*A)
    b = -C/(2*A)
    r = sqrt((B^2+C^2-4*A*D)/(4*A^2))

    (a, b, r)
end

"""
Fit a circle by using the method of Pratt
https://doi.org/10.1007/s10851-005-0482-8
Warning: not optimized
"""
function pratt(x,y)
    z = x.^2 .+ y.^2
    Mx = sum(x)
    My = sum(y)
    Mz = sum(z)
    Mxx = sum(x.^2)
    Myx = Mxy = sum(x.*y)
    Mzx = Mxz = sum(x.*z)
    Myy = sum(y.^2)
    Mzy = Myz = sum(y.*z)
    Mzz = sum(z.^2)
    n = length(x)

    B = [0  0  0 -2
         0  1  0  0
         0  0  1  0
        -2  0  0  0]
        
    M = [Mzz Mxz Myz Mz
         Mxz Mxx Mxy Mx
         Myz Mxy Myy My
         Mz  Mx  My  n]

    F = eigen(M,B)

    values = F.values
    values[values .< 0] .= Inf
    i = argmin(values)

    A,B,C,D = F.vectors[:,i]

    a = -B/(2*A)
    b = -C/(2*A)
    r = sqrt((B^2+C^2-4*A*D)/(4*A^2))

    (a, b, r)
end

import LsqFit: levenberg_marquardt, OnceDifferentiable, minimizer

"""
Gradient weighted algebraic fit
* x: vector of x coordinates
* y: vector of y coordiantes
* p0: starting values for the fit parameters(position x, position y , radius)
* kwargs are passed to `LsqFit.levenberg_marquardt`

return (position x, position y , radius)
"""
function GRAF(x,y,p0;kwargs...)
    x1 = x
    x2 = y
    z = @. x1^2 + x2^2

    model_inplace = (F, p) -> begin
        B,C,D = p
        A = 1
        @. F = (A*z + B*x1 + C*x2 + D) / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D)
    end
    jacobian_inplace = (F::Array{Float64,2},p) -> begin
        A = 1
        B,C,D = p
        
        # dA
        #@. F[:,1] = z / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D) - (A*z + B*x1 + C*x2 + D) / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D)^2 * (8*A*z-4*D)
        # dB
        @. F[:,1] = x1 / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D) - (A*z + B*x1 + C*x2 + D) / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D)^2 * (4*A*x1+2*B)
        # dC
        @. F[:,2] = x2 / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D) - (A*z + B*x1 + C*x2 + D) / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D)^2 * (4*A*x2+2*C)
        # dD
        @. F[:,3] = 1 / (4*A*(A*z+B*x1+C*x2+D)+B^2+C^2-4*A*D) 
    end
    p0_ext = [abr_to_BCD(p0...)...]
    R = OnceDifferentiable(model_inplace, jacobian_inplace, p0_ext, similar(x); inplace = true)
    results = levenberg_marquardt(R, p0_ext; kwargs...)
    coef = minimizer(results)
    BCD_to_abr(coef[1:end]...)
end

"""
convert the parametric form of 
z+B*x+C*y+D -> (x-a)²+(y-b)²-r²
"""
function BCD_to_abr(B,C,D)
    [-B/2,-C/2,sqrt(B^2/4+C^2/4-D)]
end

"""
convert the parametric form of 
z+B*x+C*y+D <- (x-a)²+(y-b)²-r²
"""
function abr_to_BCD(a,b,r)
    [-2a,-2b,a^2+b^2-r^2]
end

end # module
