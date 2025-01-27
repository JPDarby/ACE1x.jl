using ACE1x, ACE1, Test 

using ACE1: PolyTransform, transformed_jacobi, SparsePSHDegree, BasicPSH1pBasis, evaluate, rand_radial, rand_nhd
using ACE1.Random: rand_vec
using ACE1.Testing: print_tf 
using LinearAlgebra
using LinearAlgebra: qr, norm, Diagonal, I, cond
using SparseArrays
using JuLIP 
using JuLIP: evaluate, evaluate_d, evaluate!, evaluate_d!
using ACE1.Transforms: multitransform

using Test
using Printf


## === testing configs ===
ord = 4
maxdeg = 8
r0 = 2.8 
rin = 0.5 * r0
rcut = 5.5
pcut = 2
pin = 2
D = SparsePSHDegree()
transforms = Dict(
   [ (s1, s2) => PolyTransform(2, (rnn(s1)+rnn(s2))/2)
     for (s1, s2) in [(:Ti, :Ti), (:Ti, :Al), (:Al, :Al) ]] ...)

trans = multitransform(transforms; rin = 0.0, rcut = 6.0)

ninc = (pcut + pin) * (ord-1)
maxn = maxdeg + ninc 

elements = [:Ti, :Al]
species = [AtomicNumber(x) for x in elements]
zX = species[1]
Pr = transformed_jacobi(maxn, trans; pcut = 2)

##

## === Define impure and pure basis ===
ACE_B = ACE1.Utils.rpi_basis(species=species, rbasis = Pr, D=D, 
                             maxdeg=maxdeg, N=ord)
pure_rpibasis = ACE1x.Purify.pureRPIBasis(ACE_B; remove = 0)

# # get extended radial basis for testing
# spec = ACE1.get_basis_spec(ACE_B.pibasis, 1)
# maxn = maximum( maximum(b.n for b in bb.oneps) for bb in spec )
# Rn = ACE_B.pibasis.basis1p.J
# Rn_x = ACE1.transformed_jacobi(maxn, Rn.trans)

##

# === testings === 
@info("Basis construction and evaluation checks")
Nat = 15
for ntest = 1:30
    local B 
    Rs, Zs, z0 = rand_nhd(Nat, Pr.J, elements)
    B = ACE1.evaluate(pure_rpibasis, Rs, Zs, z0)
    print_tf(@test(length(pure_rpibasis) == length(B) && norm(B) > 1e-7))
end
println()


@info("isometry and permutation invariance")
for ntest = 1:30
    Rs, Zs, z0 = rand_nhd(Nat, Pr.J, elements)
    Rsp, Zsp = ACE1.rand_sym(Rs, Zs)
    print_tf(@test(ACE1.evaluate(pure_rpibasis, Rs, Zs, z0) ≈
                    ACE1.evaluate(pure_rpibasis, Rsp, Zsp, z0)))
end
println()


@info("purify checks")
for (ord, remove) in zip([2, 3, 4], [1, 2, 3])
    
    local ACE_B = ACE1.Utils.rpi_basis(species= species, rbasis=Pr, D=D, 
                                 maxdeg=maxdeg, N=ord)
    local pure_rpibasis = ACE1x.Purify.pureRPIBasis(ACE_B; remove = remove)

    # @profview pureRPIBasis(ACE_B; species = species)    
    if ord == 2 && remove == 1
        @info("Test evaluate of dimer = 0")
    elseif ord == 3 && remove == 2
        @info("Test evaluate of trimer = 0")
    elseif ord == 4 && remove == 3
        @info("Test evaluate of quadmer = 0")
    end

    for ntest = 1:30
        local B 
        z0 = rand(species)

        Zs = [rand(species) for _ = 1:ord - 1]
        rL = [ACE1.rand_radial(Pr, Zs[i], z0) for i = 1:ord - 1]
        Rs = [ JVecF(rL[i], 0, 0) for i = 1:ord - 1 ]
        B = ACE1.evaluate(pure_rpibasis, Rs, Zs, z0)
        print_tf(@test( norm(B, Inf) < 1e-12 ))
    end
    println()

    if ord == 2 && remove == 1
        @info("Test energy of dimer = 0")
        for ntest = 1:30 
            local B 
            z = rand(species)
            z0 = rand(species)
            r = ACE1.rand_radial(Pr, z, z0)
            local at = Atoms(X = [ JVecF(0, 0, 0), JVecF(r, 0, 0) ], 
                        Z = [z, z0], 
                        cell = [5.0 0 0; 0 5.0 0; 0 0.0 5.0], 
                        pbc = false)
            B = energy(pure_rpibasis, at)
            print_tf(@test( norm(B, Inf) < 1e-12 )) 
        end
        println()
    end
end

## ------------- Testing the user interface 

species = [:Ti, :Al]
model = ACE1x.acemodel(; elements = species, 
                         order = 3, 
                         totaldegree = 8,
                         pure = true,  
                         ) # default delete2b = true

pure_ace_basis = model.basis.BB[2]


Deg, maxdeg = ACE1.Utils._auto_degrees(3, 8, 1.5, nothing)
maxn = maximum(maxdeg)

dirtybasis = ACE1.ace_basis(species = AtomicNumber.(species), rbasis=pure_ace_basis.pibasis.basis1p.J, maxdeg= maxdeg, D = Deg, N = 3, )
sd_pure = ACE1x.Purify.pureRPIBasis(dirtybasis; remove = 1)

##

@info("Evaluation check")
Pr = model.basis.BB[2].pibasis.basis1p.J
Nat = 15

for ntest = 1:30  
    local Rs, Zs, z0 = rand_nhd(Nat, Pr.J, species)
    print_tf(@test(ACE1.evaluate(pure_ace_basis, Rs, Zs, z0) ≈
                   ACE1.evaluate(sd_pure, Rs, Zs, z0)))
end
println()

NL = ACE1.get_nl(pure_ace_basis)

@info("simple check on it is actually purified, we check basis of ord = 3 are zero")
for ntest = 1:30
    local B 
    z0 = rand(AtomicNumber.(species))
    Zs = [rand(AtomicNumber.(species)) for _ = 1:2]
    rL = [ACE1.rand_radial(Pr.J) for i = 1:ord - 1]
    Rs = [ JVecF(rL[i], 0, 0) for i = 1:2]
    B = ACE1.evaluate(pure_ace_basis, Rs, Zs, z0)
    print_tf(@test( norm(B[length.(NL) .== 3], Inf) < 1e-12 ))
end
println()

# ------ START CO 
c = randn(length(model.basis)) ./ (1:length(model.basis)).^2

ACE1x._set_params!(model, c)

Nat = 10 
ZZ = AtomicNumber.(species)
z0 = rand(ZZ)
Zs = [rand(ZZ) for _ = 1:Nat]
Pr = model.basis.BB[2].pibasis.basis1p.J
Rs = [ ACE1.Random.rand_sphere() * (2.7 + 2 * rand()) for i = 1:Nat]

tmp = JuLIP.alloc_temp(model.potential, Nat)
evaluate(model.potential.components[1], Rs, Zs, z0)
evaluate(model.potential.components[2], Rs, Zs, z0)
evaluate_d(model.potential.components[1], Rs, Zs, z0)
evaluate_d(model.potential.components[2], Rs, Zs, z0)

at = bulk(:Al, cubic=true) * 3
at.Z[:] .= rand(ZZ, length(at))
energy(model.potential, at)
forces(model.potential, at)
# ------ END CO
