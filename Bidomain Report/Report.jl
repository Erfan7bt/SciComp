### A Pluto.jl notebook ###
# v0.18.2

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ 2595b432-a4bc-4f64-856b-c44851122a14
begin 
    using Plots, Roots , PyPlot ,HypertextLiteral,
	ExtendableGrids,VoronoiFVM, PlutoVista,GridVisualize,LinearAlgebra, JLD2;

	# using DifferentialEquations
	
	default_plotter!(PlutoVista)
end;

# ╔═╡ f1c3201c-0a27-4c5b-9043-219291b001e0
begin 
	using PlutoUI;
	TableOfContents()
end

# ╔═╡ 735ba655-139a-4e74-ac87-2755daaf373f
begin
	using ShortCodes
	references=[
		DOI("10.1137/070680503"),
		DOI("10.5281/zenodo.3529808"),
		DOI("10.21105/joss.01848")
	]
end

# ╔═╡ e9d7e1b3-cd57-4e6d-ad95-94b5de379dab
md"""

# Bidomain Model
## Introduction

This is the report of Implementation of Bidomain Model as Formulated in [1], Usng **[VoronoiFVM.jl](https://j-fu.github.io/VoronoiFVM.jl)** [2], as the Final project of the course "Scienfic Computing" at Techinical University Of Belin in winter semster of 21/22, under Supervision of **[Dr. Juergen Fuhrmann](https://www.wias-berlin.de/people/fuhrmann/)**.  

Presented and implemented by **Alexander Quinlan** and **Erfan Baradarantohidi**.

## Bidomain Model 
The bidomain  is a system of partial differential equations used to model the propagation of electrical potential waves in myocardium. It is composed of coupled parabolic and eliptic PDEs, as well as at least one ordinary differential equation to model the ion activity through the cardic cell membrance [1].  

The electrical properties of the myocardium are generally described by the bidomain equations, a set of coupled parabolic and elliptic partial differential equations (PDEs) that represents the tissue as two separate, distinct continua - one intracellular and the other extracellular. The intracellular and the extracellular media are connected via the cell membrane, and thus the two PDEs are coupled at each point in space through a set of complex, non-linear ordinary differential equations (ODEs), which describe the ionic transport across the cell membrane. Certain modelling environments use the monodomain representation of cardiac activity, which involves solving a single parabolic PDE, by assuming either that the extracellular potentials are negligible, or that the anisotropy ratios are equal in the intracellular and the extracellular domains[3].
 
"""

# ╔═╡ 0652ee6a-7705-40e1-ae7b-9dc6b04ce0e6
md"""
# System of PDEs


$u= u_i-u_e, \ u_e \; and \; \ v \;on \: \ Q\times\Omega= [0,\ T=30] \times [0, \ L=70]$

$\frac{\partial u}{\partial t} -
	\nabla\cdot(\sigma_i(\nabla u+ \nabla u_e))
     - \frac{1}{\epsilon} f(u,v) = 0$

$\nabla\cdot(\sigma_i\nabla u+(\sigma_i +\sigma_e)\nabla u_e)=0$

$\frac{\partial v}{\partial t} - \epsilon g(u,v)=0$

We take the initial and boundary conditions $u$ and $v$ constant at the equilibrium value of the system $f(u,v)=g(u,v)=0$ and $u_e$ constant at $0$ , except on the interval $[0,L/20]$ where we fix $u$ at a supercritical value, $u(x)=2$  

So we write :  

$u_e(0,x)=0 \:\; \forall x\in \Omega$  


$u(0,x)=2 \;\;\forall x \in [0,L/20]$  

$f(u(0,x_1),v(0,x))=g(u(0,x_1),v(0,x))=0 \;\;\forall x_1 \in [L/20,L] \;\; and\;\; \forall x \in [0,L]$

Where $f(u,v) = u - \frac{u^3}{3} - v$ and $g(u,v) = u + \beta -\gamma v$
and Neumann boundary conditions:

$\partial_x u(0)=\partial_x u(L)=0 \;\; and \;\; \partial_x u_e(0)=\partial_x u_e(L)=0$
Since pure Neumann boundary conditions are ill-posed, we avoid solving a singular system with:
$u_e(0)=0,$ for 1D case it has been implemented by `boundary_dirichlet!` and in 2D case by `breaction`.
"""

# ╔═╡ b14082d3-2140-48f5-80f7-f539600a5dcc
md"""
### What do these variables describe? 
At each point in the computational domain, two electrical potential:
- ``u_i`` the **interacellular** potentionial
- ``u_e`` the **extracellular** potentionial
are recovered, representing the average of the electrical potential over the extracellular and the interacellular space, recpectively, in the neighborhoods of that point. 
- ``u=u_i - u_e`` is the **transmembrance** potential
- ``\sigma_i`` and ``\sigma_e`` are second order tensor, representing **electrical conductivity** in each spatial direcation (in this implementation, it is assumed that conductivity of heart tissue is same in each direction, hence it is constant)
- ``v`` is a lumped **ionic variable** (the ODE as last equation is not properly part of the bidomain model but rather models the ionic activity across the cellular membrance which is responsible foe electrical activation of the tissue)
- ``\epsilon`` is a paarmeter linled to the **ratio between the repolarization rate and the tissue excitation rate**
- function ``f`` and ``g`` :

$f(u,v) = u - \frac{u^3}{3} - v$
$g(u,v) = u + \beta -\gamma v$

- ``\gamma `` control **ion transport** , ``\beta`` is linked to **cell excitabillity**

"""

# ╔═╡ 4e838ed5-9373-4298-82f5-ca82864545b1
md"""
### Bidomain as a reaction-diffusion system
In order to define bidomain problem as a system of $n$ coupled PDEs so that we can handle it to VoronoiFVM we define "**reaction**" $r(u)$, ""**storage"**" $s(u)$, ""**source"**" $f$ and ""**flux"**" $\vec{j}$ in vector form as follows:  

 $\partial_t s(u) + \nabla \cdot \vec{j}(u) + r(u) = f$  

 $u = \begin{bmatrix} u\\u_e\\v\end{bmatrix}$  

 $s(u) = \begin{bmatrix} u\\0\\v\end{bmatrix}$   

 $\vec{j}(u) = \begin{bmatrix} -\sigma_i(\nabla u+\nabla u_e)\\
\sigma_i\nabla u + (\sigma_i+\sigma_e)\nabla u_e
\\0\end{bmatrix}$  

 $r(u) = \begin{bmatrix} -f(u,v)/\epsilon\\0\\ -\epsilon g(u,v)\end{bmatrix}$  

 $f = 0$.  

 storage, recation and flux terms in our system are not dependent on $\vec{x}$ and $t$, but in general they can be.
"""

# ╔═╡ b1b889d3-e505-438a-b1f9-1c105614ab74
md"""
# Discretization over Finite Volumes $\omega_k$:
#### Constructing control volumes
We construct and formulate excatly as it was done in the Lecture 
"""

# ╔═╡ 16399344-0b4f-4f8e-a364-3221448d4c17
md"""
  Assume $\Omega\subset \mathbb{R}^d$ is a polygonal domain such that
  $\partial\Omega=\bigcup_{m\in\mathcal{G}} \Gamma_m$, where $\Gamma_m$ are planar such that $\vec{n}|_{\Gamma_m}=\vec{n}_m$.

  Subdivide $\Omega$ into into a finite number of
  _control volumes_ 
  $\bar\Omega= \bigcup_{k\in \mathcal N} \bar \omega_k$
  such that 
  
  -  $\omega_k$ are open  convex domains such that  $\omega_k\cap \omega_l = \emptyset$ if
    $\omega_k\neq \omega_l$ 
  -  $\sigma_{kl}=\bar \omega_k \cap \bar \omega_l$ are either empty,
    points or straight lines.
    If $|\sigma_{kl}|>0$ we say that $\omega_k$, $\omega_l$
    are neighbours.
  -  $\vec{n}_{kl}\perp \sigma_{kl}$: normal of $\partial\omega_k$ at $\sigma_{kl}$
  -  $\mathcal{N}_k = \{l \in \mathcal{N}: |\sigma_{kl}|>0\}$: set of neighbours of $\omega_k$
  -  $\gamma_{km}=\partial\omega_k \cap \Gamma_m$: boundary part of $\partial\omega_k$
  -  $\mathcal{G}_k= \{ m \in \mathcal{G}:  |\gamma_{km}|>0\}$: set of non-empty boundary parts of $\partial\omega_k$.

  
  $\Rightarrow$ $\partial\omega_k= \left(\cup_{l\in \mathcal{N}_k} \sigma_{kl}\right)\bigcup\left(\cup_{m\in \mathcal{G}_k} \gamma_{km}\right)$

"""

# ╔═╡ 1bddacdb-ae8c-4ca5-8165-246d9a41bc5f
md"""
  To each control volume $\omega_k$ assign a _collocation
    point_: $\vec{x}_k \in \bar \omega_k$ such that\\
  
  -  _Admissibility condition_:if $l\in \mathcal N_k$ then the
    line $\vec{x}_k\vec{x}_l$ is orthogonal to $\sigma_{kl}$
    
    -  For a given function $u:\Omega \to \mathbb{R}$ this will allow to associate its value $u_k=u(\vec{x}_k)$
      as the value of an unknown at $\vec{x}_k$.
    -  For two neigboring control volumes $\omega_k, \omega_l$ , this will allow to approximate
      $\vec\nabla u \cdot \vec{n}_{kl} \approx  \frac{u_l - u_k}{h_{kl}}$
    
    
  -  _Placement of boundary unknowns at the boundary_: if
    $\omega_k$ is situated at the boundary, i.e. for 
    $|\partial \omega_k \cap \partial \Omega| >0$,
    then $\vec{x}_k \in \partial\Omega$
    
    -  This will allow to apply boundary conditions in a direct manner

"""

# ╔═╡ bf447d84-7ad8-4e9f-bfaa-30789c0532f1
md"""
### First Equation 
For $k\in\mathcal{N}$ Integrate over  each control volume $\omega_k$:
```math
\newcommand{\eps}{\varepsilon}
\newcommand{\pth}[1]{\left(#1\right)}


\begin{equation}
   \int_{\omega_k}\frac{\partial u}{\partial t}=\int_{\omega_k}\frac{1}{\eps}f(u,v)d\omega +\\
\int_{\omega_k}\nabla \cdot (\sigma_i \nabla u)d\omega + \int_{\omega_k}\nabla \cdot (\sigma_i \nabla u_e)d\omega
\end{equation}
```
By use of Gauss's thereom so the integral of divergence of flux over volume become integral of flux multiply by normal vector over bundary:
```math
\begin{align*}
    \int_{\omega_k}\frac{\partial u}{\partial t} =\int_{\omega_k}\frac{1}{\eps}f(u,v)d\omega +
    \int_{\partial\omega_k}\sigma_i \nabla u \cdot \vec{n}ds +
    \int_{\partial\omega_k}\sigma_i \nabla u_e \cdot \vec{n}ds
\end{align*}
```
Since the $\partial\Omega_k$ is either edges in domain boundary $\mathcal{G}_k$ or neighbours $\mathcal{N}_k$ 
```math
\begin{align*}
    \int_{\omega_k}\frac{\partial u}{\partial t} &=\int_{\omega_k}\frac{1}{\eps}f(u,v)d\omega + \sum_{l \in N_k}\int_{\sigma_{kl}} \sigma_i \nabla u \cdot \vec{n}_{kl}ds +
    \sum_{m \in \mathcal{G}_k}\int_{\gamma_{kl}} \sigma_i \nabla u \cdot \vec{n}_{m}ds \\
    &+ \sum_{l \in N_k}\int_{\sigma_{kl}} \sigma_i \nabla u_e \cdot \vec{n}_{kl}ds +
    \sum_{m \in \mathcal{G}_k}\int_{\gamma_{kl}} \sigma_i \nabla u_e \cdot \vec{n}_{m}ds
\end{align*}
```
Finite difference approximation of normal derivative:
```math
\begin{align*}
    h_{kl} = |x_k - x_l|\\
\sigma_i \nabla u \cdot \vec{n} \approx \sigma_i \frac{u_k - u_l}{h_{kl}}\\
    \sigma_i \nabla u_e \cdot \vec{n} \approx \sigma_i \frac{u_{e_k} - u_{e_l}}{h_{kl}}
\end{align*}
```
We also approximate integrals by the length of the edge times approximated flux: 
```math
\begin{align*}
|\omega_k|\frac{\partial u_k}{\partial t} &= \int_{w_k}\frac{1}{\eps}(u - \frac{u^3}{3} - v)d\omega + \sum_{l \in N_k} |\sigma_{kl}| \sigma_i  \frac{u_k - u_l}{h_{kl}}  + 
\sum_{m \in \mathcal{G}_k} |\gamma_{km}| \sigma_i  \frac{u_k - u_l}{h_{kl}}   \\
&+ \sum_{l \in N_k} |\sigma_{kl}| \sigma_i  \frac{u_{e_k} - u_{e_l}}{h_{kl}}  + 
\sum_{m \in \mathcal{G}_k} |\gamma_{km}| \sigma_i  \frac{u_{e_k} - u_{e_l}}{h_{kl}}  
\end{align*}
```
 Approximate reaction integral by multiplying $|\omega_k|$ and combining $u$ and $u_e$ sum:
```math
\begin{align*}
|\omega_k|\frac{\partial u_k}{\partial t} &= \frac{|\omega_k|}{\eps}\pth{u_k - \frac{u_k^3}{3} - v_k}+ \sum_{l \in N_k} |\sigma_{kl}| \sigma_i  \frac{u_k - u_l + u_{e_k} - u_{e_l}}{h_{kl}} \\
&+ \sum_{m \in \mathcal{G}_k} |\gamma_{km}| \sigma_i  \frac{u_k - u_l + u_{e_k} - u_{e_l}}{h_{kl}}  
\end{align*}
```

Then discretizing in time in forward Euler method yields:
```math
\begin{align}
\frac{|\omega_k|}{\Delta t}(u_k^{n+1} - u_k^n) = \sum_{l \in N_k} |\sigma_{kl}| \sigma_i \frac{u_k^{n} - u_l^{n} + u_{e_k}^n - u_{e_l}^{n}}{h_{kl}} 
&+ \frac{|\omega_k|}{\eps}\pth{u_k^{n} - \frac{(u_k^{n})^3}{3} - v_k^{n}}
\\+
\sum_{m \in \mathcal{G}_k} |\gamma_{km}| \sigma_i  \frac{u_k^{n} - u_l^{n} + u_{e_k}^{n} - u_{e_l}^{n}}{h_{kl}} 
\end{align}
```
As $u_k^n = u(\vec{x_k},n\Delta t)$
"""

# ╔═╡ 616e63fa-e7d6-42f1-b332-408a0734b531
md"""
### Second Equation  

After following same procedure as the discretization of Equation 1:
 Since there is no stoarge term in this equation
  $u_k=u_k^n = u(\vec{x_k},n\Delta t)$
```math
\begin{align}
\sum_{l \in N_k} |\sigma_{kl}| \sigma_i \frac{u_k - u_l}{h_{kl}}
+ \sum_{l \in N_k} |\sigma_{kl}| \pth{\sigma_i+\sigma_e}  \frac{u_{e_k} - u_{e_l}}{h_{kl}}  \\
+\sum_{m \in \mathcal{G}_k} |\gamma_{km}| \sigma_i \frac{u_k - u_l}{h_{kl}}  
+\sum_{m \in \mathcal{G}_k} |\gamma_{km}| (\sigma_i+\sigma_e)  \frac{u_{e_k} - u_{e_l}}{h_{kl}}=0
\end{align}
```
"""

# ╔═╡ 3b4d813c-eca4-4f36-8d89-29b2f9ebbb2b
md"""
### Last Equation 

```math
\begin{align*}
\int_{\omega_k}\frac{\partial v}{\partial t} d\omega = \int_{\omega_k} \eps(u + \beta - \gamma v)d\omega 
\end{align*}
```
Approximation of Integrals:
```math
\begin{align*}
|\omega_k|\frac{\partial v_k}{\partial t} = \eps |\omega_k| (u_k + \beta - \gamma v_k) 
\end{align*}
```
Then forward discretizing in time :
```math
\begin{align*}
\frac{|\omega_k|}{\Delta t}(v_k^{n+1} - v_k^{n}) = \eps |\omega_k| (u_k^{n} + \beta - \gamma v_k^{n})
\end{align*}
```
"""

# ╔═╡ 9cb6fd91-6d07-48e5-a5ee-2fbc439c8570
md"""
### Alternative Time Discretization
For a real parameter `` 0 \leq \theta \leq 1 ``, it is possible to replace the current value with the convex cominiation of next and current value such that:
```math
\begin {align*}
u_k^n \Rightarrow u_k^{\theta}=\theta u_k^{n+1}+(1-\theta)u_k^{n}
\end{align*}
```
by setting ``\theta=0`` we got Explicit/Forward Euler scheme , other than  ``\theta=1``, Implicit\Backward Euler scheme or ``\theta=\frac{1}{2}``, Crank-Nicolson scheme is defined.

Solution methods in [VoronoiFVM.jl](https://j-fu.github.io/VoronoiFVM.jl) can be done with Implicit Euler by kwarg `tstep` given. 
"""

# ╔═╡ b5aad722-99cb-424d-a2af-a37cefac1a59
md"""
### Observations

We successfully recreated the 1d problem without much difficulty, but had a lot of trouble recreating the spiral pattern observed in [1]. It turns out that the solution is very sensitive to spatial step-size-- less than roughly 100 cells per L=70 in each dimension would result in an incorrect solution that did not display conductivity in that direction. To avoid this, we ran our spiral solution overnight with N=120x120 and ``\Delta t = 10^{-2}``.
"""

# ╔═╡ daf3c9ee-01ff-494b-a0b0-a6a6560b75cc
md"""
# Simulations
"""

# ╔═╡ 62b11f3a-7d3d-4790-bacf-df10f297888d
md"""
 ### Parameters 
"""

# ╔═╡ 768f4e8d-a8f4-4f20-8b68-e180521edcff
begin
	# shared parameters
	
	ϵ = 0.1
	β = 1
	γ = 0.5
	
	species = ["u", "u_e", "v"]
	# the anistropic conductivity has not been studied 
	σᵢ_anisotropic = 25*[0.263 0; 0 0.0263]
	σₑ_anisotropic = 25*[0.263 0; 0 0.1087]
	
	σᵢ = 1
	σₑ = 1
	
	L = 70
	tf = 70
	Δt = 1e-1;

	# Storage and replay
	overwrite_storage = false
	compression = 100
end;

# ╔═╡ fb6aa962-a7d6-479b-bf11-52b8be2483f8
# 1D Parameters
begin
	# 1d
	N = 500;
end

# ╔═╡ df3a31b9-2a70-44d5-8a7e-5d427dc327cc
# 2D Parameters
begin
	Δt₂ = 1e-1;
end

# ╔═╡ 6dcd9399-8bd2-48a6-8e06-5af201d4f730
md"""
### Deriving Initial Condition
"""

# ╔═╡ 54b8a5a0-2ca5-4973-b7b4-35d420e675c2
begin
	#by setting f and g equal to zero
	 ut(u0)=u0^3 + 3*u0 + 6
	 u₀=find_zero(ut,0)
	 v₀= 2*u₀ + 2
end;

# ╔═╡ a0249b52-5f13-4d37-9709-a069b065278d
function u_init(x)
	#Function contain IC for 1_D case
	u = u₀; v = v₀
	if 0 ≤ x ≤ L/20
		u = 2
	end
	uₑ = 0
	return [u, uₑ, v]
end

# ╔═╡ 9b06c02d-ec46-4590-acac-821733809c6f
md"""
# Problem Implementation in VoronoiFVM
 ### Physics Defintion
"""

# ╔═╡ bb37d88a-13e4-4a8d-a852-175d34a06afd
function storage(f,u,node)
	f[1]= u[1]
	f[2]= 0
	f[3]= u[3]
end

# ╔═╡ adbc6875-1d0f-4e49-9abd-f12eced388ef
begin 
	f(u,v)= u - u^3/3 - v
	g(u,v)= u + β - γ*v
end;

# ╔═╡ 7a367571-9e02-4449-808a-c319997c3df9
function reaction(y,u,node)
    y[1]= -f(u[1],u[3])/ϵ
	y[2]= 0
	y[3]= -ϵ*g(u[1],u[3])
end

# ╔═╡ b484a050-2e8a-4a0f-b975-62692be5cea9
function flux(f,u,edge)
	f[1] = -σᵢ*((u[1,2] - u[1,1]) + (u[2,2] - u[2,1]))
	f[2] = σᵢ*(u[1,2] - u[1,1]) + (σᵢ+σₑ) * (u[2,2] - u[2,1])
	f[3] = 0
end

# ╔═╡ 7528709e-39f3-462a-8845-5ee2c78dec7e
"""
From the paper: "To avoid solving a singular system we add the condition u_e(0) = 0"
"""
function breaction(f,u,node)
		if node.coord[:,node.index] == [0, 0, 0]
			f[2] = 0
		end
end

# ╔═╡ 593f1fa3-ce33-41b1-aaa6-492d13a6584a
md"""
### 1D Problem
"""

# ╔═╡ 64a70e08-dea2-40bc-8db9-cc3ced84ac2f
function bcondition_1d(f)
	boundary_neumann!(f,species=1,region=1,value=0)
	boundary_neumann!(f,species=1,region=2,value=0)

	boundary_neumann!(f,species=2,region=1,value=0)
	boundary_neumann!(f,species=2,region=2,value=0)

	boundary_dirichlet!(f,species=2,region=1,value=0)
end

# ╔═╡ 089b0d84-3c9f-499f-8e41-9e6e71b74036
function grid_1d(N)
	X = LinRange(0,L,N)
	return grid=simplexgrid(X)
end

# ╔═╡ b38b57f6-ad80-4a50-b8bd-952d4d3e4866
function bidomain_1D(;N=100, Δt=1e-1, tf=30, Plotter=Plots)
	grid = grid_1d(N)
    
	#system Def
	
	physics = VoronoiFVM.Physics(
		storage=storage, flux=flux, reaction=reaction, breaction=breaction)
	
	system=VoronoiFVM.System(
		grid, physics, unknown_storage=:sparse) 
	
	enable_species!(system, species=[1,2,3])
	
	bcondition_1d(system)
	
	system

	# Solving ODE
	
	init = unknowns(system)
	
	inival = map(u_init, grid)
	init .= [tuple[k] for tuple in inival, k in 1:3]'
	
	U = unknowns(system)
	Sol = copy(init)
	tgrid = 0:Δt:tf
	for t ∈ tgrid[2:end]
		VoronoiFVM.solve!(U, init, system; tstep=Δt)
		init .= U
		Sol = cat(Sol, copy(U), dims=3)
	end
	vis = GridVisualizer(resolution=(400,300), dim=1, Plotter=Plots)
    return grid, tgrid, Sol, vis, system
end

# ╔═╡ 6e2fab73-30a8-4209-ba55-529f9c77cbc3
begin 
	xgrid, tgrid, sol, vis, system= bidomain_1D(N=N, Δt=Δt);
	system
end

# ╔═╡ 28dcd70a-952d-492a-84f8-ee04eb83e360
function plot_at_t(t,vis,xgrid,sol)
	species = ["u", "u_e", "v"]
	tₛ = Int16(round(t/Δt))+1
	scalarplot!(vis, xgrid, sol[1,:,tₛ], linestyle=:solid)
	scalarplot!(vis, xgrid, sol[2,:,tₛ], linestyle=:dash)
	plotted_sol = scalarplot!(
		vis, xgrid, sol[3,:,tₛ], linestyle=:dot, legend=:best, show=true)
	for (i,spec) ∈ zip(2 .* (1:length(species)), species)
		plotted_sol[1][i][:label] = spec
	end
	Plots.plot!(labels=species)
	Plots.plot!(ylims=(-2.5,2.5))
	Plots.plot!(title="1D solution overtime ")
	plotted_sol
end

# ╔═╡ e7cc8d45-4816-4623-9d4e-0d84d78c8fd2
begin
	anim_tf = 30
	step_size =3*Δt
	anim = @animate for t in 0:step_size:anim_tf
		plot_at_t(t,vis,xgrid,sol)
	end
	gif(anim)
end

# ╔═╡ 03fa9a1b-2e6a-4189-8f1b-8a702c9dcbf0
function contour_plot(spec)
	PyPlot.clf()
	Xgrid = xgrid[Coordinates][:]
	Tgrid = tgrid
	Zgrid = sol[spec,:,:]
	PyPlot.suptitle("Space-time contour plot of "*species[spec])
	
	PyPlot.contourf(Xgrid,Tgrid,Zgrid',cmap="viridis",levels=100)
	axes=PyPlot.gca()
	axes.set_aspect(2)
	PyPlot.colorbar()

	PyPlot.xlabel(L"x")
	PyPlot.ylabel(L"t")
	figure=PyPlot.gcf()
	figure.set_size_inches(5,5)
	figure
end

# ╔═╡ ad2b0f17-789c-47b8-8775-45331823036e
function contour_2d_at_t(spec, t, Δt, xgrid, sol)
	tₛ = Int16(round(t/Δt))+1
	p = scalarplot(
		xgrid,sol[spec,:,tₛ], Plotter=PyPlot, colormap=:viridis, 
		title=species[spec]*
		" at t="*string(t))
	PyPlot.xlabel(L"x")
	PyPlot.ylabel(L"y")
	figure=PyPlot.gcf()
	figure.set_size_inches(5,5)
	figure
end

# ╔═╡ df344c5f-06e6-41cf-adf8-63a184445388
@bind species_1d PlutoUI.Select([1, 2, 3])

# ╔═╡ 4828996d-6084-4279-b4d9-aa52254682c2
contour_plot(species_1d)

# ╔═╡ c7b6354b-398f-43cb-b3f1-ab410ecbea02
md"""
# 2D Problems
"""

# ╔═╡ 65194fa2-a30c-4423-b5c6-eab8507af235
""""
	Create the 2d Grid
"""
function grid_2d(N)
	X = LinRange(0,L,N[1])
	Y = LinRange(0,L,N[2])
	grid2d = simplexgrid(X,Y)
	return grid2d
end

# ╔═╡ 6a2270d4-cb7c-41a1-a300-d87079666145
"""
Initialize the 2d problem
"""
function u_2d(x,y)
	u = u₀ 
	v = v₀
	uₑ = 0

	# Rectangle in middle
	mid = L/2
	# if mid ≤ x ≤ 5 + mid && mid ≤ y ≤ 5 + mid
	# 	u = 2
	# end

	# Classic
	if 0 ≤ x ≤ 3.5 && 0 ≤ y ≤ 70
		u = 2
	end
	if 31 ≤ x ≤ 39 && 0 ≤ y ≤ 35
		v = 2
	end
	return [u, uₑ, v]
end


# ╔═╡ 54c521f5-2165-442d-baee-64b9f413d99f
function u_2d_as_1d(x,y)
	return u_init(x)
end

# ╔═╡ 51d646e9-a066-4068-9598-b9673bdda8f8
"""
2D Boundaries
"""
function bcondition_2d(f)
	for species ∈ [1 2] # Species 2 as well??
		for region ∈ [1 2 3 4]
			boundary_neumann!(f,species=species,region=region,value=0)
		end
	end
end

# ╔═╡ cbcbcfac-9e76-4a44-b2a9-40c4e8d089d6
function bidomain_2d(;N=100, Δt=1e-1, tf=70, Plotter=Plots, setup="1d")
	xgrid = grid_2d(N)
    
	#system Def
	
	physics = VoronoiFVM.Physics(
		storage=storage, flux=flux, reaction=reaction, breaction=breaction)
	
	system=VoronoiFVM.System(
		xgrid, physics, unknown_storage=:sparse) 
	
	enable_species!(system, species=[1,2,3])
	
	bcondition_2d(system)
	
	init = unknowns(system)
	U = unknowns(system)
	if setup == "1d"
		inival = map(u_2d_as_1d, xgrid)
	else
		inival = map(u_2d, xgrid)
	end
	init .= [tuple[k] for tuple in inival, k in 1:3]'
	
	SolArray = copy(init)
	vis = GridVisualizer(resolution=(400,300), dim=2, Plotter=Plots)
	# tgrid = 0:Δt:T
	tgrid = 0:Δt:tf
	for t ∈ tgrid[2:end]
		if t % 1 == 0
			println(string("At t=", t))
			# contour_2d_at_t(species_select,t,Δt₂,xgrid,SolArray)
		end
		VoronoiFVM.solve!(U, init, system; tstep=Δt)
		init .= U
		SolArray = cat(SolArray, copy(U), dims=3)
	end
    return xgrid, tgrid, SolArray, vis, system
end

# ╔═╡ af5a7305-7154-4053-8f8c-375c07f141e2
md"""
### 2D Problem with 1D Setup
"""

# ╔═╡ 4d6b1dc5-4a62-4b86-81de-c9a5e4c76d60
begin
	N₂ = (100,25)
	xgrid₂, tgrid₂, sol₂, vis₂, sys₂ = bidomain_2d(N=N₂,tf=tf, Δt=Δt₂, Plotter=PyPlot);
end

# ╔═╡ 4cfec74c-46de-4281-a8c1-7b5a76ea851f
@bind species_select PlutoUI.Select([1, 2, 3])

# ╔═╡ 3f00ecee-2003-4c14-aaa5-d525f3b11607
@bind time₂ PlutoUI.Slider(0:tf,show_value=true)

# ╔═╡ 9f834292-40d4-4e70-a31b-8bb37884176d
contour_2d_at_t(species_select,time₂,Δt₂,xgrid₂,sol₂)

# ╔═╡ 07009ae2-b8fa-4f6c-ad76-7a9901d3c304
md"""
### 2D Problem with 2D Setup
#### Using precompiled data
"""

# ╔═╡ 49c346dc-1a3f-4c3e-ab28-68f00c2b7ca1
@bind species_replay PlutoUI.Select([1, 2, 3])

# ╔═╡ fe52e576-d533-4a79-9707-ee867ea9df1c
@bind time_replay PlutoUI.Slider(0:tf,show_value=true)

# ╔═╡ 7695a4ff-15d1-4978-8c84-f22bc8cb9ccc
contour_2d_at_t(
	species_replay,
	time_replay,
	Δt₂ * compression / 10, # This was run at 1/10 the timestep so dividing by another factor of 10
	load_object("xgrid.jld2"),
	load_object("sol.jld2")
)

# ╔═╡ ceebe18c-2e85-4e5a-bcad-437bc60453b7
begin
	if overwrite_storage
		xgrid3, tgrid3, sol3, vis3, sys3 = bidomain_2d(N=N₂,T=tf, Δt=Δt₂, Plotter=PyPlot, setup="2d");

	end
end

# ╔═╡ f22b494e-f0f9-4058-88f6-29aeac95b2f4
# Compress (only store every 100 timepts) and save the full solution for graphing
begin
	if overwrite_storage # Only store the solution if we really want to overwrite
		sol_compressed = cat(sol3[:, :, 1], sol3[:, :, compression], dims=3)
		for i ∈  2:70
			sol_compressed = cat(sol_compressed, sol3[:, :, i*compression], dims=3)
		end
		save_object("sol.dat", sol_compressed)
		save_object("xgrid.dat", xgrid3)
	end
end

# ╔═╡ 2457d1c5-53b7-4237-ab52-f6efa4d73be3
md"""
# Ways to Improve Performance

Generally to improve performance we can take advantage of different time discretization scheme, such as 2nd order methods. We also tried to use [**DifferentialEquations.jl**](https://github.com/SciML/DifferentialEquations.jl)
,but we couldn't implement it properly.
"""

# ╔═╡ e913062d-bd53-4afd-b725-e60a0f5cdd22
md"""
# Summary 
 We implemented three diffrent cases of Bidomain Problem with different Intial condition, in 1D case, travelling wave moving through the domain with constant speed is shown, further we drive a 2D model with 1D test problem in on a 2d grid (with a small number of Y coordinates) as an optional topic; we succesfully drive a 2D case with special intial condition which ends in a planner spiral wave that is used again as intial condition in [1]. 
"""

# ╔═╡ 40e01b91-bbc1-41ba-a7b3-72c859fc8ae5
md"""
# Bibliography
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
ExtendableGrids = "cfc395e8-590f-11e8-1f13-43a2532b2fa8"
GridVisualize = "5eed8a63-0fb0-45eb-886d-8d5a387d12b8"
HypertextLiteral = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
JLD2 = "033835bb-8acc-5ee8-8aae-3f567f8a3819"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
PlutoVista = "646e1f28-b900-46d7-9d87-d554eb38a413"
PyPlot = "d330b81b-6aea-500a-939a-2ce795aea3ee"
Roots = "f2b01f46-fcfa-551c-844a-d8ac1e96c665"
ShortCodes = "f62ebe17-55c5-4640-972f-b59c0dd11ccf"
VoronoiFVM = "82b139dc-5afc-11e9-35da-9b9bdfd336f3"

[compat]
ExtendableGrids = "~0.9.5"
GridVisualize = "~0.5.1"
HypertextLiteral = "~0.9.3"
JLD2 = "~0.4.22"
Plots = "~1.27.5"
PlutoUI = "~0.7.38"
PlutoVista = "~0.8.13"
PyPlot = "~2.10.0"
Roots = "~2.0.0"
ShortCodes = "~0.3.3"
VoronoiFVM = "~0.16.3"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[AbstractTrees]]
git-tree-sha1 = "03e0550477d86222521d254b741d470ba17ea0b5"
uuid = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
version = "0.3.4"

[[Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "af92965fb30777147966f58acb05da51c5616b5f"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.3.3"

[[ArgCheck]]
git-tree-sha1 = "a3a402a35a2f7e0b87828ccabbd5ebfbebe356b4"
uuid = "dce04be8-c92d-5529-be00-80e4d2c0e197"
version = "2.3.0"

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "62e51b39331de8911e4a7ff6f5aaf38a5f4cc0ae"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.2.0"

[[ArrayInterface]]
deps = ["Compat", "IfElse", "LinearAlgebra", "Requires", "SparseArrays", "Static"]
git-tree-sha1 = "c933ce606f6535a7c7b98e1d86d5d1014f730596"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "5.0.7"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[AutoHashEquals]]
git-tree-sha1 = "45bb6705d93be619b81451bb2006b7ee5d4e4453"
uuid = "15f4f7f2-30c1-5605-9d31-71845cf9641f"
version = "0.2.0"

[[BangBang]]
deps = ["Compat", "ConstructionBase", "Future", "InitialValues", "LinearAlgebra", "Requires", "Setfield", "Tables", "ZygoteRules"]
git-tree-sha1 = "b15a6bc52594f5e4a3b825858d1089618871bf9d"
uuid = "198e06fe-97b7-11e9-32a5-e1d131e6ad66"
version = "0.3.36"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[Baselet]]
git-tree-sha1 = "aebf55e6d7795e02ca500a689d326ac979aaf89e"
uuid = "9718e550-a3fa-408a-8086-8db961cd8217"
version = "0.1.1"

[[Bijections]]
git-tree-sha1 = "705e7822597b432ebe152baa844b49f8026df090"
uuid = "e2ed5e7c-b2de-5872-ae92-c73ca462fb04"
version = "0.1.3"

[[Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "9950387274246d08af38f6eef8cb5480862a435f"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.14.0"

[[ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "bf98fa45a0a4cee295de98d4c1462be26345b9a1"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.2"

[[CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[ColorSchemes]]
deps = ["ColorTypes", "Colors", "FixedPointNumbers", "Random"]
git-tree-sha1 = "12fc73e5e0af68ad3137b886e3f7c1eacfca2640"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.17.1"

[[ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "024fe24d83e4a5bf5fc80501a314ce0d1aa35597"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.0"

[[Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "417b0ed7b8b838aa6ca0a87aadf1bb9eb111ce40"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.8"

[[Combinatorics]]
git-tree-sha1 = "08c8b6831dc00bfea825826be0bc8336fc369860"
uuid = "861a8166-3701-5b0c-9a16-15d98fcdc6aa"
version = "1.0.2"

[[CommonSolve]]
git-tree-sha1 = "68a0743f578349ada8bc911a5cbd5a2ef6ed6d1f"
uuid = "38540f10-b2f7-11e9-35d8-d573e4eb0ff2"
version = "0.2.0"

[[CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "b153278a25dd42c65abbf4e62344f9d22e59191b"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.43.0"

[[CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[CompositeTypes]]
git-tree-sha1 = "d5b014b216dc891e81fea299638e4c10c657b582"
uuid = "b152e2b5-7a66-4b01-a709-34e65c35f657"
version = "0.1.2"

[[CompositionsBase]]
git-tree-sha1 = "455419f7e328a1a2493cabc6428d79e951349769"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.1"

[[Conda]]
deps = ["Downloads", "JSON", "VersionParsing"]
git-tree-sha1 = "6e47d11ea2776bc5627421d59cdcc1296c058071"
uuid = "8f4d0f93-b110-5947-807f-2305c1781a2d"
version = "1.7.0"

[[ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f74e9d5388b8620b4cee35d4c5a618dd4dc547f4"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.3.0"

[[Contour]]
deps = ["StaticArrays"]
git-tree-sha1 = "9f02045d934dc030edad45944ea80dbd1f0ebea7"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.5.7"

[[DataAPI]]
git-tree-sha1 = "cc70b17275652eb47bc9e5f81635981f13cea5c8"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.9.0"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "3daef5523dd2e769dad2365274f760ff5f282c7d"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.11"

[[DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[DefineSingletons]]
git-tree-sha1 = "0fba8b706d0178b4dc7fd44a96a92382c9065c2c"
uuid = "244e2a9f-e319-4986-a169-4d1fe445cd52"
version = "0.1.2"

[[DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[DensityInterface]]
deps = ["InverseFunctions", "Test"]
git-tree-sha1 = "80c3e8639e3353e5d2912fb3a1916b8455e2494b"
uuid = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
version = "0.4.0"

[[DiffResults]]
deps = ["StaticArrays"]
git-tree-sha1 = "c18e98cba888c6c25d1c3b048e4b3380ca956805"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.0.3"

[[DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "dd933c4ef7b4c270aacd4eb88fa64c147492acf0"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.10.0"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[Distributions]]
deps = ["ChainRulesCore", "DensityInterface", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns", "Test"]
git-tree-sha1 = "5a4168170ede913a2cd679e53c2123cb4b889795"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.53"

[[DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

[[DomainSets]]
deps = ["CompositeTypes", "IntervalSets", "LinearAlgebra", "StaticArrays", "Statistics"]
git-tree-sha1 = "5f5f0b750ac576bcf2ab1d7782959894b304923e"
uuid = "5b8099bc-c8ec-5219-889f-1d9e522a28bf"
version = "0.5.9"

[[Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[DynamicPolynomials]]
deps = ["DataStructures", "Future", "LinearAlgebra", "MultivariatePolynomials", "MutableArithmetics", "Pkg", "Reexport", "Test"]
git-tree-sha1 = "d0fa82f39c2a5cdb3ee385ad52bc05c42cb4b9f0"
uuid = "7c1d4256-1411-5781-91ec-d7bc3513ac07"
version = "0.4.5"

[[EarCut_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3f3a2501fa7236e9b911e0f7a588c657e822bb6d"
uuid = "5ae413db-bbd1-5e63-b57d-d24a61df00f5"
version = "2.2.3+0"

[[ElasticArrays]]
deps = ["Adapt"]
git-tree-sha1 = "a0fcc1bb3c9ceaf07e1d0529c9806ce94be6adf9"
uuid = "fdbdab4c-e67f-52f5-8c3f-e7b388dad3d4"
version = "1.2.9"

[[EllipsisNotation]]
deps = ["ArrayInterface"]
git-tree-sha1 = "d064b0340db45d48893e7604ec95e7a2dc9da904"
uuid = "da5c29d0-fa7d-589e-88eb-ea29b0a81949"
version = "1.5.0"

[[Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bad72f730e9e91c08d9427d5e8db95478a3c323d"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.4.8+0"

[[ExprTools]]
git-tree-sha1 = "56559bbef6ca5ea0c0818fa5c90320398a6fbf8d"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.8"

[[ExtendableGrids]]
deps = ["AbstractTrees", "Dates", "DocStringExtensions", "ElasticArrays", "InteractiveUtils", "LinearAlgebra", "Printf", "Random", "SparseArrays", "StaticArrays", "Test", "WriteVTK"]
git-tree-sha1 = "cec19e62fc126df338de88585f45a763f7601bd3"
uuid = "cfc395e8-590f-11e8-1f13-43a2532b2fa8"
version = "0.9.5"

[[ExtendableSparse]]
deps = ["DocStringExtensions", "LinearAlgebra", "Printf", "Requires", "SparseArrays", "SuiteSparse", "Test"]
git-tree-sha1 = "eb3393e4de326349a4b5bccd9b17ed1029a2d0ca"
uuid = "95c220a8-a1cf-11e9-0c77-dbfce5f500b3"
version = "0.6.7"

[[FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "Pkg", "Zlib_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "d8a578692e3077ac998b50c0217dfd67f21d1e5f"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.0+0"

[[FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "80ced645013a5dbdc52cf70329399c35ce007fae"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.13.0"

[[FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "246621d23d1f43e3b9c368bf3b72b2331a27c286"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "0.13.2"

[[FiniteDiff]]
deps = ["ArrayInterface", "LinearAlgebra", "Requires", "SparseArrays", "StaticArrays"]
git-tree-sha1 = "56956d1e4c1221000b7781104c58c34019792951"
uuid = "6a86dc24-6348-571c-b903-95158fe2bd41"
version = "2.11.0"

[[FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions", "StaticArrays"]
git-tree-sha1 = "1bd6fc0c344fc0cbee1f42f8d2e7ec8253dda2d2"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.25"

[[FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "87eb71354d8ec1a96d4a7636bd57a7347dde3ef9"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.10.4+0"

[[FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "51d2dfe8e590fbd74e7a842cf6d13d8a2f45dc01"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.6+0"

[[GR]]
deps = ["Base64", "DelimitedFiles", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Printf", "Random", "RelocatableFolders", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "af237c08bda486b74318c8070adb96efa6952530"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.64.2"

[[GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Pkg", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "cd6efcf9dc746b06709df14e462f0a3fe0786b1e"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.64.2+0"

[[GeometryBasics]]
deps = ["EarCut_jll", "IterTools", "LinearAlgebra", "StaticArrays", "StructArrays", "Tables"]
git-tree-sha1 = "83ea630384a13fc4f002b77690bc0afeb4255ac9"
uuid = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
version = "0.4.2"

[[Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "a32d672ac2c967f3deb8a81d828afc739c838a06"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.68.3+2"

[[Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[Graphs]]
deps = ["ArnoldiMethod", "Compat", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "57c021de207e234108a6f1454003120a1bf350c4"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.6.0"

[[GridVisualize]]
deps = ["ColorSchemes", "Colors", "DocStringExtensions", "ElasticArrays", "ExtendableGrids", "GeometryBasics", "HypertextLiteral", "LinearAlgebra", "Observables", "OrderedCollections", "PkgVersion", "Printf", "StaticArrays"]
git-tree-sha1 = "5d845bccf5d690879f4f5f01c7112e428b1fa543"
uuid = "5eed8a63-0fb0-45eb-886d-8d5a387d12b8"
version = "0.5.1"

[[Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[HTTP]]
deps = ["Base64", "Dates", "IniFile", "Logging", "MbedTLS", "NetworkOptions", "Sockets", "URIs"]
git-tree-sha1 = "0fa77022fe4b511826b39c894c90daf5fce3334a"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "0.9.17"

[[HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[HypertextLiteral]]
git-tree-sha1 = "2b078b5a615c6c0396c77810d92ee8c6f470d238"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.3"

[[IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[IfElse]]
git-tree-sha1 = "debdd00ffef04665ccbb3e150747a77560e8fad1"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.1"

[[Inflate]]
git-tree-sha1 = "f5fc07d4e706b84f72d54eedcc1c13d92fb0871c"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.2"

[[IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[InitialValues]]
git-tree-sha1 = "4da0f88e9a39111c2fa3add390ab15f3a44f3ca3"
uuid = "22cec73e-a1b8-11e9-2c92-598750a2cf9c"
version = "0.3.1"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[IntervalSets]]
deps = ["Dates", "EllipsisNotation", "Statistics"]
git-tree-sha1 = "bcf640979ee55b652f3b01650444eb7bbe3ea837"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.5.4"

[[InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "91b5dcf362c5add98049e6c29ee756910b03051d"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.3"

[[IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[IterTools]]
git-tree-sha1 = "fa6287a4469f5e048d763df38279ee729fbd44e5"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.4.0"

[[IterativeSolvers]]
deps = ["LinearAlgebra", "Printf", "Random", "RecipesBase", "SparseArrays"]
git-tree-sha1 = "1169632f425f79429f245113b775a0e3d121457c"
uuid = "42fd0dbc-a981-5370-80f2-aaf504508153"
version = "0.9.2"

[[IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[JLD2]]
deps = ["FileIO", "MacroTools", "Mmap", "OrderedCollections", "Pkg", "Printf", "Reexport", "TranscodingStreams", "UUIDs"]
git-tree-sha1 = "81b9477b49402b47fbe7f7ae0b252077f53e4a08"
uuid = "033835bb-8acc-5ee8-8aae-3f567f8a3819"
version = "0.4.22"

[[JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[JSON3]]
deps = ["Dates", "Mmap", "Parsers", "StructTypes", "UUIDs"]
git-tree-sha1 = "8c1f668b24d999fb47baf80436194fdccec65ad2"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.9.4"

[[JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b53380851c6e6664204efb2e62cd24fa5c47e4ba"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.2+0"

[[LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[LabelledArrays]]
deps = ["ArrayInterface", "ChainRulesCore", "LinearAlgebra", "MacroTools", "StaticArrays"]
git-tree-sha1 = "fbd884a02f8bf98fd90c53c1c9d2b21f9f30f42a"
uuid = "2ee39098-c373-598a-b85f-a56591580800"
version = "1.8.0"

[[Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "Printf", "Requires"]
git-tree-sha1 = "6f14549f7760d84b2db7a9b10b88cd3cc3025730"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.14"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "7739f837d6447403596a75d19ed01fd08d6f56bf"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.3.0+3"

[[Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "42b62845d70a619f063a7da093d995ec8e15e778"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+1"

[[Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "c9551dd26e31ab17b86cbd00c2ede019c08758eb"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.3.0+1"

[[Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[LightXML]]
deps = ["Libdl", "XML2_jll"]
git-tree-sha1 = "e129d9391168c677cd4800f5c0abb1ed8cb3794f"
uuid = "9c8b4983-aa76-5018-a973-4c85ecc9e179"
version = "0.9.0"

[[LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "a970d55c2ad8084ca317a4658ba6ce99b7523571"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.12"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "Random", "Sockets"]
git-tree-sha1 = "1c38e51c3d08ef2278062ebceade0e46cefc96fe"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.0.3"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[Measures]]
git-tree-sha1 = "e498ddeee6f9fdb4551ce855a46f54dbd900245f"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.1"

[[Memoize]]
deps = ["MacroTools"]
git-tree-sha1 = "2b1dfcba103de714d31c033b5dacc2e4a12c7caa"
uuid = "c03570c3-d221-55d1-a50c-7939bbd78826"
version = "0.4.4"

[[Metatheory]]
deps = ["AutoHashEquals", "DataStructures", "Dates", "DocStringExtensions", "Parameters", "Reexport", "TermInterface", "ThreadsX", "TimerOutputs"]
git-tree-sha1 = "0886d229caaa09e9f56bcf1991470bd49758a69f"
uuid = "e9d8d322-4543-424a-9be4-0cc815abe26c"
version = "1.3.3"

[[MicroCollections]]
deps = ["BangBang", "InitialValues", "Setfield"]
git-tree-sha1 = "6bb7786e4f24d44b4e29df03c69add1b63d88f01"
uuid = "128add7d-3638-4c79-886c-908ea0c25c34"
version = "0.1.2"

[[Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[MultivariatePolynomials]]
deps = ["ChainRulesCore", "DataStructures", "LinearAlgebra", "MutableArithmetics"]
git-tree-sha1 = "393fc4d82a73c6fe0e2963dd7c882b09257be537"
uuid = "102ac46a-7ee4-5c85-9060-abc95bfdeaa3"
version = "0.4.6"

[[MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "ba8c0f8732a24facba709388c74ba99dcbfdda1e"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.0.0"

[[NaNMath]]
git-tree-sha1 = "b086b7ea07f8e38cf122f5016af580881ac914fe"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "0.3.7"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[Observables]]
git-tree-sha1 = "fe29afdef3d0c4a8286128d4e45cc50621b1e43d"
uuid = "510215fc-4207-5dde-b226-833fc4488ee2"
version = "0.4.0"

[[Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ab05aa4cc89736e95915b01e7279e61b1bfe33b8"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.14+0"

[[OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[PCRE_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b2a7af664e098055a7529ad1a900ded962bca488"
uuid = "2f80f16e-611a-54ab-bc61-aa92de5b98fc"
version = "8.44.0+0"

[[PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "e8185b83b9fc56eb6456200e873ce598ebc7f262"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.7"

[[Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[Parsers]]
deps = ["Dates"]
git-tree-sha1 = "621f4f3b4977325b9128d5fae7a8b4829a0c2222"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.2.4"

[[Pixman_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b4f5d02549a10e20780a24fce72bea96b6329e29"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.40.1+0"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[PkgVersion]]
deps = ["Pkg"]
git-tree-sha1 = "a7a7e1a88853564e551e4eba8650f8c38df79b37"
uuid = "eebad327-c553-4316-9ea0-9fa01ccd7688"
version = "0.1.1"

[[PlotThemes]]
deps = ["PlotUtils", "Statistics"]
git-tree-sha1 = "8162b2f8547bc23876edd0c5181b27702ae58dce"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "3.0.0"

[[PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "Printf", "Random", "Reexport", "Statistics"]
git-tree-sha1 = "bb16469fd5224100e422f0b027d26c5a25de1200"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.2.0"

[[Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "GeometryBasics", "JSON", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "Requires", "Scratch", "Showoff", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "Unzip"]
git-tree-sha1 = "88ee01b02fba3c771ac4dce0dfc4ecf0cb6fb772"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.27.5"

[[PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "670e559e5c8e191ded66fa9ea89c97f10376bb4c"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.38"

[[PlutoVista]]
deps = ["ColorSchemes", "Colors", "DocStringExtensions", "GridVisualize", "HypertextLiteral", "UUIDs"]
git-tree-sha1 = "118d1871e3511131bae2196e238d0054bd9a62b0"
uuid = "646e1f28-b900-46d7-9d87-d554eb38a413"
version = "0.8.13"

[[Preferences]]
deps = ["TOML"]
git-tree-sha1 = "d3538e7f8a790dc8903519090857ef8e1283eecd"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.5"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[PyCall]]
deps = ["Conda", "Dates", "Libdl", "LinearAlgebra", "MacroTools", "Serialization", "VersionParsing"]
git-tree-sha1 = "1fc929f47d7c151c839c5fc1375929766fb8edcc"
uuid = "438e738f-606a-5dbb-bf0a-cddfbfd45ab0"
version = "1.93.1"

[[PyPlot]]
deps = ["Colors", "LaTeXStrings", "PyCall", "Sockets", "Test", "VersionParsing"]
git-tree-sha1 = "14c1b795b9d764e1784713941e787e1384268103"
uuid = "d330b81b-6aea-500a-939a-2ce795aea3ee"
version = "2.10.0"

[[Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "ad368663a5e20dbb8d6dc2fddeefe4dae0781ae8"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+0"

[[QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "78aadffb3efd2155af139781b8a8df1ef279ea39"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.4.2"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[RecipesBase]]
git-tree-sha1 = "6bf3f380ff52ce0832ddd3a2a7b9538ed1bcca7d"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.2.1"

[[RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "RecipesBase"]
git-tree-sha1 = "dc1e451e15d90347a7decc4221842a022b011714"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.5.2"

[[RecursiveArrayTools]]
deps = ["Adapt", "ArrayInterface", "ChainRulesCore", "DocStringExtensions", "FillArrays", "LinearAlgebra", "RecipesBase", "Requires", "StaticArrays", "Statistics", "ZygoteRules"]
git-tree-sha1 = "bfe14f127f3e7def02a6c2b1940b39d0dabaa3ef"
uuid = "731186ca-8d62-57ce-b412-fbd966d074cd"
version = "2.26.3"

[[Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[Referenceables]]
deps = ["Adapt"]
git-tree-sha1 = "e681d3bfa49cd46c3c161505caddf20f0e62aaa9"
uuid = "42d2dcc6-99eb-4e98-b66c-637b7d73030e"
version = "0.1.2"

[[RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "cdbd3b1338c72ce29d9584fdbe9e9b70eeb5adca"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "0.1.3"

[[Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "bf3188feca147ce108c76ad82c2792c57abe7b1f"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.0"

[[Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "68db32dff12bb6127bac73c209881191bf0efbb7"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.3.0+0"

[[Roots]]
deps = ["CommonSolve", "Printf", "Setfield"]
git-tree-sha1 = "e382260f6482c27b5062eba923e36fde2f5ab0b9"
uuid = "f2b01f46-fcfa-551c-844a-d8ac1e96c665"
version = "2.0.0"

[[RuntimeGeneratedFunctions]]
deps = ["ExprTools", "SHA", "Serialization"]
git-tree-sha1 = "cdc1e4278e91a6ad530770ebb327f9ed83cf10c4"
uuid = "7e49a35a-f44a-4d26-94aa-eba1b4ca6b47"
version = "0.5.3"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[SciMLBase]]
deps = ["ArrayInterface", "CommonSolve", "ConstructionBase", "Distributed", "DocStringExtensions", "IteratorInterfaceExtensions", "LinearAlgebra", "Logging", "RecipesBase", "RecursiveArrayTools", "StaticArrays", "Statistics", "Tables", "TreeViews"]
git-tree-sha1 = "61159e034c4cb36b76ad2926bb5bf8c28cc2fb12"
uuid = "0bca4576-84f4-4d90-8ffe-ffa030f20462"
version = "1.29.0"

[[Scratch]]
deps = ["Dates"]
git-tree-sha1 = "0b4b7f1393cff97c33891da2a0bf69c6ed241fda"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.1.0"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "Requires"]
git-tree-sha1 = "38d88503f695eb0301479bc9b0d4320b378bafe5"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "0.8.2"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[ShortCodes]]
deps = ["Base64", "CodecZlib", "HTTP", "JSON3", "Memoize", "UUIDs"]
git-tree-sha1 = "0fcc38215160e0a964e9b0f0c25dcca3b2112ad1"
uuid = "f62ebe17-55c5-4640-972f-b59c0dd11ccf"
version = "0.3.3"

[[Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[SparseDiffTools]]
deps = ["Adapt", "ArrayInterface", "Compat", "DataStructures", "FiniteDiff", "ForwardDiff", "Graphs", "LinearAlgebra", "Requires", "SparseArrays", "StaticArrays", "VertexSafeGraphs"]
git-tree-sha1 = "314a07e191ea4a5ea5a2f9d6b39f03833bde5e08"
uuid = "47a9eef4-7e08-11e9-0b38-333d64bd3804"
version = "1.21.0"

[[SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "5ba658aeecaaf96923dce0da9e703bd1fe7666f9"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.1.4"

[[SplittablesBase]]
deps = ["Setfield", "Test"]
git-tree-sha1 = "39c9f91521de844bad65049efd4f9223e7ed43f9"
uuid = "171d559e-b47b-412a-8079-5efa626c420e"
version = "0.1.14"

[[Static]]
deps = ["IfElse"]
git-tree-sha1 = "87e9954dfa33fd145694e42337bdd3d5b07021a6"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.6.0"

[[StaticArrays]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "4f6ec5d99a28e1a749559ef7dd518663c5eca3d5"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.4.3"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "8d7530a38dbd2c397be7ddd01a424e4f411dcc41"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.2.2"

[[StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "8977b17906b0a1cc74ab2e3a05faa16cf08a8291"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.16"

[[StatsFuns]]
deps = ["ChainRulesCore", "InverseFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "5950925ff997ed6fb3e985dcce8eb1ba42a0bbe7"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "0.9.18"

[[StructArrays]]
deps = ["Adapt", "DataAPI", "StaticArrays", "Tables"]
git-tree-sha1 = "57617b34fa34f91d536eb265df67c2d4519b8b98"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.6.5"

[[StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "d24a825a95a6d98c385001212dc9020d609f2d4f"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.8.1"

[[SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[SymbolicUtils]]
deps = ["AbstractTrees", "Bijections", "ChainRulesCore", "Combinatorics", "ConstructionBase", "DataStructures", "DocStringExtensions", "DynamicPolynomials", "IfElse", "LabelledArrays", "LinearAlgebra", "Metatheory", "MultivariatePolynomials", "NaNMath", "Setfield", "SparseArrays", "SpecialFunctions", "StaticArrays", "TermInterface", "TimerOutputs"]
git-tree-sha1 = "bfa211c9543f8c062143f2a48e5bcbb226fd790b"
uuid = "d1185830-fcd6-423d-90d6-eec64667417b"
version = "0.19.7"

[[Symbolics]]
deps = ["ConstructionBase", "DataStructures", "DiffRules", "Distributions", "DocStringExtensions", "DomainSets", "IfElse", "Latexify", "Libdl", "LinearAlgebra", "MacroTools", "Metatheory", "NaNMath", "RecipesBase", "Reexport", "Requires", "RuntimeGeneratedFunctions", "SciMLBase", "Setfield", "SparseArrays", "SpecialFunctions", "StaticArrays", "SymbolicUtils", "TermInterface", "TreeViews"]
git-tree-sha1 = "9230e74d316442051e8a6c9c9af89a04be1e6106"
uuid = "0c5d862f-8b57-4792-8d23-62f2024744c7"
version = "4.2.2"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "5ce79ce186cc678bbb5c5681ca3379d1ddae11a1"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.7.0"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[TermInterface]]
git-tree-sha1 = "7aa601f12708243987b88d1b453541a75e3d8c7a"
uuid = "8ea1fca8-c5ef-4a55-8b96-4e9afe9c9a3c"
version = "0.2.3"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[ThreadsX]]
deps = ["ArgCheck", "BangBang", "ConstructionBase", "InitialValues", "MicroCollections", "Referenceables", "Setfield", "SplittablesBase", "Transducers"]
git-tree-sha1 = "d223de97c948636a4f34d1f84d92fd7602dc555b"
uuid = "ac1d9e8a-700a-412c-b207-f0111f4b6c0d"
version = "0.1.10"

[[TimerOutputs]]
deps = ["ExprTools", "Printf"]
git-tree-sha1 = "d60b0c96a16aaa42138d5d38ad386df672cb8bd8"
uuid = "a759f4b9-e2f1-59dc-863e-4aeb61b1ea8f"
version = "0.5.16"

[[TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

[[Transducers]]
deps = ["Adapt", "ArgCheck", "BangBang", "Baselet", "CompositionsBase", "DefineSingletons", "Distributed", "InitialValues", "Logging", "Markdown", "MicroCollections", "Requires", "Setfield", "SplittablesBase", "Tables"]
git-tree-sha1 = "c76399a3bbe6f5a88faa33c8f8a65aa631d95013"
uuid = "28d57a85-8fef-5791-bfe6-a80928e7c999"
version = "0.4.73"

[[TreeViews]]
deps = ["Test"]
git-tree-sha1 = "8d0d7a3fe2f30d6a7f833a5f19f7c7a5b396eae6"
uuid = "a2a6695c-b41b-5b7d-aed9-dbfdeacea5d7"
version = "0.3.0"

[[URIs]]
git-tree-sha1 = "97bbe755a53fe859669cd907f2d96aee8d2c1355"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.3.0"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[Unzip]]
git-tree-sha1 = "34db80951901073501137bdbc3d5a8e7bbd06670"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.1.2"

[[VersionParsing]]
git-tree-sha1 = "58d6e80b4ee071f5efd07fda82cb9fbe17200868"
uuid = "81def892-9a0e-5fdd-b105-ffc91e053289"
version = "1.3.0"

[[VertexSafeGraphs]]
deps = ["Graphs"]
git-tree-sha1 = "8351f8d73d7e880bfc042a8b6922684ebeafb35c"
uuid = "19fa3120-7c27-5ec5-8db8-b0b0aa330d6f"
version = "0.2.0"

[[VoronoiFVM]]
deps = ["DiffResults", "DocStringExtensions", "ExtendableGrids", "ExtendableSparse", "ForwardDiff", "GridVisualize", "IterativeSolvers", "JLD2", "LinearAlgebra", "Parameters", "Printf", "RecursiveArrayTools", "Requires", "SparseArrays", "SparseDiffTools", "StaticArrays", "Statistics", "SuiteSparse", "Symbolics", "Test"]
git-tree-sha1 = "254b5472a9f3ec970a08b24b76cba4bf1d79f3e6"
uuid = "82b139dc-5afc-11e9-35da-9b9bdfd336f3"
version = "0.16.3"

[[Wayland_jll]]
deps = ["Artifacts", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "3e61f0b86f90dacb0bc0e73a0c5a83f6a8636e23"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.19.0+0"

[[Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4528479aa01ee1b3b4cd0e6faef0e04cf16466da"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.25.0+0"

[[WriteVTK]]
deps = ["Base64", "CodecZlib", "FillArrays", "LightXML", "TranscodingStreams"]
git-tree-sha1 = "bff2f6b5ff1e60d89ae2deba51500ce80014f8f6"
uuid = "64499a7a-5c06-52f2-abe2-ccb03c286192"
version = "1.14.2"

[[XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "1acf5bdf07aa0907e0a37d3718bb88d4b687b74a"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.9.12+0"

[[XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "5be649d550f3f4b95308bf0183b82e2582876527"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.6.9+4"

[[Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4e490d5c960c314f33885790ed410ff3a94ce67e"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.9+4"

[[Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fe47bd2247248125c428978740e18a681372dd4"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.3+4"

[[Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6783737e45d3c59a4a4c4091f5f88cdcf0908cbb"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.0+3"

[[Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "daf17f441228e7a3833846cd048892861cff16d6"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.13.0+3"

[[Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "926af861744212db0eb001d9e40b5d16292080b2"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.0+4"

[[Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "4bcbf660f6c2e714f87e960a171b119d06ee163b"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.2+4"

[[Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "5c8424f8a67c3f2209646d4425f3d415fee5931d"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.27.0+4"

[[Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "79c31e7844f6ecf779705fbc12146eb190b7d845"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.4.0+3"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e45044cd873ded54b6a5bac0eb5c971392cf1927"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.2+0"

[[ZygoteRules]]
deps = ["MacroTools"]
git-tree-sha1 = "8c1a8e4dfacb1fd631745552c8db35d0deb09ea0"
uuid = "700de1a5-db45-46bc-99cf-38207098b444"
version = "0.2.2"

[[libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"

[[x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "ece2350174195bb31de1a63bea3a41ae1aa593b6"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "0.9.1+5"
"""

# ╔═╡ Cell order:
# ╟─2595b432-a4bc-4f64-856b-c44851122a14
# ╟─f1c3201c-0a27-4c5b-9043-219291b001e0
# ╟─e9d7e1b3-cd57-4e6d-ad95-94b5de379dab
# ╟─0652ee6a-7705-40e1-ae7b-9dc6b04ce0e6
# ╟─b14082d3-2140-48f5-80f7-f539600a5dcc
# ╟─4e838ed5-9373-4298-82f5-ca82864545b1
# ╟─b1b889d3-e505-438a-b1f9-1c105614ab74
# ╟─16399344-0b4f-4f8e-a364-3221448d4c17
# ╟─1bddacdb-ae8c-4ca5-8165-246d9a41bc5f
# ╟─bf447d84-7ad8-4e9f-bfaa-30789c0532f1
# ╟─616e63fa-e7d6-42f1-b332-408a0734b531
# ╟─3b4d813c-eca4-4f36-8d89-29b2f9ebbb2b
# ╟─9cb6fd91-6d07-48e5-a5ee-2fbc439c8570
# ╟─b5aad722-99cb-424d-a2af-a37cefac1a59
# ╟─daf3c9ee-01ff-494b-a0b0-a6a6560b75cc
# ╟─62b11f3a-7d3d-4790-bacf-df10f297888d
# ╠═768f4e8d-a8f4-4f20-8b68-e180521edcff
# ╠═fb6aa962-a7d6-479b-bf11-52b8be2483f8
# ╠═df3a31b9-2a70-44d5-8a7e-5d427dc327cc
# ╟─6dcd9399-8bd2-48a6-8e06-5af201d4f730
# ╠═54b8a5a0-2ca5-4973-b7b4-35d420e675c2
# ╠═a0249b52-5f13-4d37-9709-a069b065278d
# ╟─9b06c02d-ec46-4590-acac-821733809c6f
# ╠═bb37d88a-13e4-4a8d-a852-175d34a06afd
# ╠═adbc6875-1d0f-4e49-9abd-f12eced388ef
# ╠═7a367571-9e02-4449-808a-c319997c3df9
# ╠═b484a050-2e8a-4a0f-b975-62692be5cea9
# ╠═7528709e-39f3-462a-8845-5ee2c78dec7e
# ╟─593f1fa3-ce33-41b1-aaa6-492d13a6584a
# ╠═64a70e08-dea2-40bc-8db9-cc3ced84ac2f
# ╠═089b0d84-3c9f-499f-8e41-9e6e71b74036
# ╠═b38b57f6-ad80-4a50-b8bd-952d4d3e4866
# ╠═6e2fab73-30a8-4209-ba55-529f9c77cbc3
# ╠═28dcd70a-952d-492a-84f8-ee04eb83e360
# ╟─e7cc8d45-4816-4623-9d4e-0d84d78c8fd2
# ╠═03fa9a1b-2e6a-4189-8f1b-8a702c9dcbf0
# ╠═ad2b0f17-789c-47b8-8775-45331823036e
# ╠═df344c5f-06e6-41cf-adf8-63a184445388
# ╠═4828996d-6084-4279-b4d9-aa52254682c2
# ╠═c7b6354b-398f-43cb-b3f1-ab410ecbea02
# ╠═65194fa2-a30c-4423-b5c6-eab8507af235
# ╠═6a2270d4-cb7c-41a1-a300-d87079666145
# ╠═54c521f5-2165-442d-baee-64b9f413d99f
# ╠═51d646e9-a066-4068-9598-b9673bdda8f8
# ╠═cbcbcfac-9e76-4a44-b2a9-40c4e8d089d6
# ╠═af5a7305-7154-4053-8f8c-375c07f141e2
# ╠═4d6b1dc5-4a62-4b86-81de-c9a5e4c76d60
# ╠═4cfec74c-46de-4281-a8c1-7b5a76ea851f
# ╠═3f00ecee-2003-4c14-aaa5-d525f3b11607
# ╠═9f834292-40d4-4e70-a31b-8bb37884176d
# ╟─07009ae2-b8fa-4f6c-ad76-7a9901d3c304
# ╠═49c346dc-1a3f-4c3e-ab28-68f00c2b7ca1
# ╠═fe52e576-d533-4a79-9707-ee867ea9df1c
# ╠═7695a4ff-15d1-4978-8c84-f22bc8cb9ccc
# ╠═ceebe18c-2e85-4e5a-bcad-437bc60453b7
# ╠═f22b494e-f0f9-4058-88f6-29aeac95b2f4
# ╟─2457d1c5-53b7-4237-ab52-f6efa4d73be3
# ╟─e913062d-bd53-4afd-b725-e60a0f5cdd22
# ╟─40e01b91-bbc1-41ba-a7b3-72c859fc8ae5
# ╟─735ba655-139a-4e74-ac87-2755daaf373f
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
