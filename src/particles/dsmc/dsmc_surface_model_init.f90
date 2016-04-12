#include "boltzplatz.h"

MODULE MOD_DSMC_SurfModelInit
!===================================================================================================================================
! Initialization of DSMC
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE InitDSMCSurfModel
  MODULE PROCEDURE InitDSMCSurfModel
END INTERFACE

! INTERFACE FinalizeDSMCSurfModel
!   MODULE PROCEDURE FinalizeDSMCSurfModel
! END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC                       :: InitDSMCSurfModel
! PUBLIC                       :: FinalizeDSMCSurfModel
!===================================================================================================================================

CONTAINS


SUBROUTINE InitDSMCSurfModel()
!===================================================================================================================================
! Init of DSMC Vars
!===================================================================================================================================
! MODULES
USE MOD_Globals,                ONLY : abort
USE MOD_Mesh_Vars,              ONLY : nElems, nBCSides, BC
USE MOD_DSMC_Vars,              ONLY : Adsorption
USE MOD_PARTICLE_Vars,          ONLY : nSpecies, PDM
USE MOD_PARTICLE_Vars,          ONLY : KeepWallParticles, PEM
USE MOD_ReadInTools
USE MOD_Particle_Boundary_Vars, ONLY : nSurfSample, SurfMesh, PartBound
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES                                                                      !
  CHARACTER(32)                    :: hilf , hilf2  
  INTEGER                          :: iSpec, iSide, iSurf, p, q, IDcounter
  REAL                             :: maxPart, SurfArea
!===================================================================================================================================
KeepWallParticles = GETLOGICAL('Particles-KeepWallParticles','.FALSE.')
IF (KeepWallParticles) THEN
  ALLOCATE(PDM%ParticleAtWall(1:PDM%maxParticleNumber)  , &
          PDM%PartAdsorbSideIndx(1:3,1:PDM%maxParticleNumber))
  PDM%ParticleAtWall(1:PDM%maxParticleNumber) = .FALSE.
  ALLOCATE(PEM%wNumber(1:nElems))
END IF
! allocate info and constants
ALLOCATE( Adsorption%AdsorpInfo(1:nSpecies),&
          Adsorption%Constants(1:nSpecies))
DO iSpec = 1,nSpecies
#if (PP_TimeDiscMethod==42)
  ALLOCATE( Adsorption%AdsorpInfo(iSpec)%NumOfAds(1:SurfMesh%nSides),&
            Adsorption%AdsorpInfo(iSpec)%NumOfDes(1:SurfMesh%nSides))
#endif
  ALLOCATE( Adsorption%Constants(iSpec)%MaxCoverage(1:SurfMesh%nSides),&
            Adsorption%Constants(iSpec)%InitStick(1:SurfMesh%nSides),&
            Adsorption%Constants(iSpec)%PrefactorStick(1:SurfMesh%nSides),&
            Adsorption%Constants(iSpec)%Adsorbexp(1:SurfMesh%nSides),&
            Adsorption%Constants(iSpec)%Nu_a(1:SurfMesh%nSides),&
            Adsorption%Constants(iSpec)%Nu_b(1:SurfMesh%nSides),&
            Adsorption%Constants(iSpec)%DesorbEnergy(1:SurfMesh%nSides),&
            Adsorption%Constants(iSpec)%Intensification(1:SurfMesh%nSides))
END DO
! initialize info and constants
DO iSpec = 1,nSpecies
#if (PP_TimeDiscMethod==42)
  DO iSide = 1,SurfMesh%nSides
    Adsorption%AdsorpInfo(iSpec)%NumOfAds(iSide)=0
    Adsorption%AdsorpInfo(iSpec)%NumOfDes(iSide)=0
  END DO
#endif
  WRITE(UNIT=hilf,FMT='(I2)') iSpec
  Adsorption%Constants(iSpec)%MaxCoverage(:) = GETREAL('Part-Species'//TRIM(hilf)//'-MaximumCoverage','0.')
  Adsorption%Constants(iSpec)%InitStick(:) = GETREAL('Part-Species'//TRIM(hilf)//'-InitialStick','0.')
  Adsorption%Constants(iSpec)%PrefactorStick(:) = GETREAL('Part-Species'//TRIM(hilf)//'-PrefactorStick','0.')
  Adsorption%Constants(iSpec)%Adsorbexp(:) = GETINT('Part-Species'//TRIM(hilf)//'-Adsorbexp','1')
  Adsorption%Constants(iSpec)%Nu_a(:) = GETREAL('Part-Species'//TRIM(hilf)//'-Nu-a','0.')
  Adsorption%Constants(iSpec)%Nu_b(:) = GETREAL('Part-Species'//TRIM(hilf)//'-Nu-b','0.')
  Adsorption%Constants(iSpec)%DesorbEnergy(:) = GETREAL('Part-Species'//TRIM(hilf)//'-Desorption-Energy-K','1.')
  Adsorption%Constants(iSpec)%Intensification(:) = GETREAL('Part-Species'//TRIM(hilf)//'-Intensification-K','0.')
END DO
#if (PP_TimeDiscMethod==42)
    Adsorption%AdsorpInfo(iSpec)%MeanProbAds = 0.
    Adsorption%AdsorpInfo(iSpec)%MeanProbDes = 0.
    Adsorption%TPD = GETLOGICAL('Particles-DSMC-Adsorption-doTPD','.FALSE.')
    Adsorption%TPD_beta = GETREAL('Particles-DSMC-Adsorption-TPD-Beta','0.')
    Adsorption%TPD_Temp = 0.
#endif
! allocate and initialize adsorption variables
ALLOCATE( Adsorption%Coverage(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%ProbAds(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%ProbDes(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%SumDesorbPart(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%SumAdsorbPart(1:nSurfSample,1:nSurfSample,1:SurfMesh%nSides,1:nSpecies),&
          Adsorption%SurfSideToGlobSideMap(1:SurfMesh%nSides),&
          Adsorption%DensSurfAtoms(1:SurfMesh%nSides))
IDcounter = 0         
DO iSide = 1,nBCSides 
  IF (PartBound%TargetBoundCond(PartBound%MapToPartBC(BC(iSide))).EQ.PartBound%ReflectiveBC) THEN
    IDcounter = IDcounter + 1
    Adsorption%SurfSideToGlobSideMap(IDcounter) = iSide
  END IF
END DO
DO iSurf = 1,SurfMesh%nSides
  WRITE(UNIT=hilf,FMT='(I2)') iSurf
  Adsorption%DensSurfAtoms(iSurf) = GETREAL('Particles-Surface'//TRIM(hilf)//'-AtomsDensity','1.5E+19')
END DO
DO iSpec = 1,nSpecies
  WRITE(UNIT=hilf,FMT='(I2)') iSpec
  Adsorption%Coverage(:,:,:,iSpec) = GETREAL('Part-Species'//TRIM(hilf)//'-InitialCoverage','0.')
END DO
Adsorption%ProbAds(:,:,:,:) = 0.
Adsorption%ProbDes(:,:,:,:) = 0.
Adsorption%SumDesorbPart(:,:,:,:) = 0
Adsorption%SumAdsorbPart(:,:,:,:) = 0

END SUBROUTINE InitDSMCSurfModel

END MODULE MOD_DSMC_SurfModelInit