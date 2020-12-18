!==================================================================================================================================
! Copyright (c) 2010 - 2018 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
!
! This file is part of PICLas (gitlab.com/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"

MODULE MOD_DSMC_AmbipolarDiffusion
!===================================================================================================================================
! Module for use of a background gas for the simulation of trace species (if number density of bg gas is multiple orders of
! magnitude larger than the trace species)
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE AD_InsertParticles
  MODULE PROCEDURE AD_InsertParticles
END INTERFACE

INTERFACE AD_DeleteParticles
  MODULE PROCEDURE AD_DeleteParticles
END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: AD_InsertParticles, AD_DeleteParticles
!===================================================================================================================================

CONTAINS

SUBROUTINE AD_InsertParticles(iPartIndx_Node, nPart, iPartIndx_NodeTotalAmbi, TotalPartNum)
!===================================================================================================================================
!> Creating electrons for each actual ion simulation particle
!===================================================================================================================================
! MODULES
USE MOD_Globals                
USE MOD_part_emission_tools    ,ONLY: DSMC_SetInternalEnr_LauxVFD
USE MOD_DSMC_Vars              ,ONLY: BGGas, SpecDSMC, CollisMode, DSMC, PartStateIntEn,AmbipolElecVelo,RadialWeighting
USE MOD_DSMC_Vars              ,ONLY: DSMCSumOfFormedParticles, newAmbiParts, iPartIndx_NodeNewAmbi, DSMC_RHS
USE MOD_DSMC_PolyAtomicModel   ,ONLY: DSMC_SetInternalEnr_Poly
USE MOD_PARTICLE_Vars          ,ONLY: PDM, PartSpecies, PartState, PEM, PartPosRef, Species, nSpecies,VarTimeStep, PartMPF, Symmetry
USE MOD_part_emission_tools    ,ONLY: SetParticleChargeAndMass,SetParticleMPF,CalcVelocity_maxwell_lpn
USE MOD_Particle_Tracking_Vars ,ONLY: DoRefmapping, TrackingMethod
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemEpsOneCell
USE MOD_Particle_Mesh_Tools    ,ONLY: ParticleInsideQuad3D
USE MOD_Particle_Localization  ,ONLY: PartInElemCheck
USE MOD_Eval_xyz               ,ONLY: GetPositionInRefElem
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers    ,ONLY: LBStartTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(INOUT)             :: iPartIndx_Node(1:nPart)
INTEGER,INTENT(INOUT)             :: nPart, TotalPartNum
INTEGER,INTENT(INOUT),ALLOCATABLE :: iPartIndx_NodeTotalAmbi(:)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iNewPart, iPart, PositionNbr, LocalElemID, iLoop, nNewElectrons, IonIndX(nPart), iElem, PartNum
REAL              :: MaxPos(3), MinPos(3), Vec3D(3), Det(6,2), RefPos(3), RandomPos(3)
LOGICAL           :: InsideFlag
#if USE_LOADBALANCE
REAL              :: tLBStart
#endif /*USE_LOADBALANCE*/
!===================================================================================================================================
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/

MaxPos = -HUGE(MaxPos)
MinPos = HUGE(MinPos)
iNewPart=0
PositionNbr = 0
nNewElectrons = 0

DO iLoop = 1, nPart
  iPart = iPartIndx_Node(iLoop)
  MaxPos(1) = MAX(MaxPos(1),PartState(1,iPart))
  MaxPos(2) = MAX(MaxPos(2),PartState(2,iPart))
  MaxPos(3) = MAX(MaxPos(3),PartState(3,iPart))
  MinPos(1) = MIN(MinPos(1),PartState(1,iPart))
  MinPos(2) = MIN(MinPos(2),PartState(2,iPart))
  MinPos(3) = MIN(MinPos(3),PartState(3,iPart))
  IF(Species(PartSpecies(iPart))%ChargeIC.GT.0.0) THEN
    nNewElectrons = nNewElectrons + 1
    IonIndX(nNewElectrons) = iPart
  END IF
END DO
ALLOCATE(iPartIndx_NodeTotalAmbi(nPart + nNewElectrons))
iPartIndx_NodeTotalAmbi(1:nPart) = iPartIndx_Node(1:nPart)
TotalPartNum = nPart

DO iLoop = 1, nNewElectrons
  DSMCSumOfFormedParticles = DSMCSumOfFormedParticles + 1
  PositionNbr = PDM%nextFreePosition(DSMCSumOfFormedParticles+PDM%CurrentNextFreePosition)
  IF (PositionNbr.EQ.0) THEN
    CALL Abort(&
__STAMP__&
,'ERROR in Ambipolar Diffusion: MaxParticleNumber too small!')
  END IF
  InsideFlag=.FALSE.
  iElem = PEM%GlobalElemID(iPartIndx_Node(1))
  DO WHILE(.NOT.InsideFlag)
    CALL RANDOM_NUMBER(Vec3D(1:3))
    RandomPos(1:3) = MinPos(1:3)+Vec3D(1:3)*(MaxPos(1:3)-MinPos(1:3))
    IF(Symmetry%Order.LE.2) RandomPos(3) = 0.
    IF(Symmetry%Order.LE.1) RandomPos(2) = 0.
    SELECT CASE(TrackingMethod)
      CASE(TRIATRACKING)
        CALL ParticleInsideQuad3D(RandomPos,iElem,InsideFlag,Det)
      CASE(TRACING)
        CALL PartInElemCheck(RandomPos,iPart,iElem,InsideFlag)
      CASE(REFMAPPING)
        CALL GetPositionInRefElem(RandomPos,RefPos,iElem)
        IF (MAXVAL(ABS(RefPos)).LE.ElemEpsOneCell(iElem)) InsideFlag=.TRUE.
    END SELECT
  END DO
  PartState(1:3,PositionNbr) = RandomPos(1:3)
  PartSpecies(PositionNbr) = DSMC%AmbiDiffElecSpec
  PEM%GlobalElemID(PositionNbr) = iElem
  PDM%ParticleInside(PositionNbr) = .true.
  PartState(4:6,PositionNbr) = AmbipolElecVelo(IonIndX(iLoop))%ElecVelo(1:3)
  DSMC_RHS(1:3,PositionNbr) = 0.0
  DEALLOCATE(AmbipolElecVelo(IonIndX(iLoop))%ElecVelo)
  IF ((CollisMode.EQ.2).OR.(CollisMode.EQ.3)) THEN
    PartStateIntEn( 1,PositionNbr) = 0.
    PartStateIntEn( 2,PositionNbr) = 0.
    IF (DSMC%ElectronicModel)   PartStateIntEn( 3,PositionNbr) = 0.
  END IF
  IF(RadialWeighting%DoRadialWeighting) PartMPF(PositionNbr) = PartMPF(IonIndX(iLoop))
  IF(VarTimeStep%UseVariableTimeStep) VarTimeStep%ParticleTimeStep(PositionNbr) = VarTimeStep%ParticleTimeStep(IonIndX(iLoop))
  iPartIndx_NodeTotalAmbi(nPart+iLoop) = PositionNbr
END DO
! Output variable
TotalPartNum = nPart + nNewElectrons
! Variable used for allocation
PartNum = TotalPartNum
! In case of the background gas, additional particles will be added
IF(BGGas%NumberOfSpecies.GT.0) PartNum = PartNum + TotalPartNum

newAmbiParts = 0
IF (ALLOCATED(iPartIndx_NodeNewAmbi)) DEALLOCATE(iPartIndx_NodeNewAmbi)
ALLOCATE(iPartIndx_NodeNewAmbi(PartNum))

#if USE_LOADBALANCE
CALL LBPauseTime(LB_DSMC,tLBStart)
#endif /*USE_LOADBALANCE*/
END SUBROUTINE AD_InsertParticles

SUBROUTINE AD_DeleteParticles(iPartIndx_Node, nPart)
!===================================================================================================================================
!> Deletes all electron created for the collision process
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PARTICLE_Vars,      ONLY : PDM, PartSpecies, Species, PartState, PEM
USE MOD_Particle_Analyze,   ONLY : PARTISELECTRON
USE MOD_DSMC_Vars,          ONLY : AmbipolElecVelo, newAmbiParts, iPartIndx_NodeNewAmbi, DSMC_RHS
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(INOUT)       :: iPartIndx_Node(:), nPart
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                     :: iPart, iLoop, nElectron, nIon
INTEGER                     :: ElecIndx(2*nPart), IonIndX(2*nPart)
!===================================================================================================================================
nElectron =0; nIon = 0
DO iLoop = 1, nPart
  iPart = iPartIndx_Node(iLoop)
  IF (PDM%ParticleInside(iPart)) THEN
    IF(PARTISELECTRON(iPart)) THEN
      nElectron = nElectron + 1
      ElecIndx(nElectron) = iPart
    END IF
    IF(Species(PartSpecies(iPart))%ChargeIC.GT.0.0) THEN
      nIon = nIon + 1
      IonIndX(nIon) = iPart
    END IF
  END IF
END DO
DO iLoop = 1, newAmbiParts
  iPart = iPartIndx_NodeNewAmbi(iLoop)
  IF (PDM%ParticleInside(iPart)) THEN
    IF(PARTISELECTRON(iPart)) THEN
      nElectron = nElectron + 1
      ElecIndx(nElectron) = iPart
    END IF
    IF(Species(PartSpecies(iPart))%ChargeIC.GT.0.0) THEN
      nIon = nIon + 1
      IonIndX(nIon) = iPart
    END IF
  END IF
END DO

IF(nIon.NE.nElectron) THEN
  IPWRITE(*,*) 'nPart', nPart, 'newAmbiParts', newAmbiParts
  DO iLoop = 1, nPart
    iPart = iPartIndx_Node(iLoop)
    IPWRITE(*,*) 'inside', iPart, PDM%ParticleInside(iPart), PartSpecies(iPart), Species(PartSpecies(iPart))%ChargeIC, PEM%GlobalElemID(iPart)
  END DO
  IPWRITE(*,*) 'newParts!!!!!'
  DO iLoop = 1, newAmbiParts
    iPart = iPartIndx_NodeNewAmbi(iLoop)
    IPWRITE(*,*) 'inside', iPart, PDM%ParticleInside(iPart), PartSpecies(iPart), Species(PartSpecies(iPart))%ChargeIC, PEM%GlobalElemID(iPart)
  END DO
  CALL abort(__STAMP__&
      ,'ERROR: Number of electrons and ions is not equal for ambipolar diffusion: ' &
      ,IntInfoOpt=nIon-nElectron)
END IF

DO iLoop = 1, nElectron
  IF (ALLOCATED(AmbipolElecVelo(IonIndX(iLoop))%ElecVelo)) DEALLOCATE(AmbipolElecVelo(IonIndX(iLoop))%ElecVelo)
  ALLOCATE(AmbipolElecVelo(IonIndX(iLoop))%ElecVelo(3))
  AmbipolElecVelo(IonIndX(iLoop))%ElecVelo(1:3) = PartState(4:6,ElecIndx(iLoop)) + DSMC_RHS(1:3,ElecIndx(iLoop))
  PDM%ParticleInside(ElecIndx(iLoop)) = .FALSE.
END DO

DEALLOCATE(iPartIndx_NodeNewAmbi)

END SUBROUTINE AD_DeleteParticles

END MODULE MOD_DSMC_AmbipolarDiffusion
