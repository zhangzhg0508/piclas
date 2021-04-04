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

MODULE MOD_Particle_Sampling_Adapt
!===================================================================================================================================
!> Subroutines required for the sampling of macroscopic properties at elements with a boundary for the porous and adaptive boundary
!> conditions
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
PUBLIC :: InitAdaptiveBCSampling, AdaptiveBCSampling, FinalizeParticleSamplingAdaptive
!===================================================================================================================================

CONTAINS

SUBROUTINE InitAdaptiveBCSampling()
!===================================================================================================================================
!> Routine counts the number of elements, where macroscopic values are to be sampled
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_IO_HDF5
USE MOD_ReadInTools
USE MOD_Particle_Sampling_Vars
USE MOD_HDF5_INPUT              ,ONLY: ReadArray, DatasetExists, GetDataSize
USE MOD_Mesh_Vars               ,ONLY: offsetElem, nElems, SideToElem
USE MOD_Particle_Vars           ,ONLY: Species, nSpecies
USE MOD_Particle_Surfaces_Vars  ,ONLY: BCdata_auxSF
USE MOD_Restart_Vars            ,ONLY: DoRestart,RestartFile, DoMacroscopicRestart, MacroRestartValues
USE MOD_SurfaceModel_Vars       ,ONLY: nPorousBC
USE MOD_Particle_Boundary_Vars  ,ONLY: nPorousSides, PorousBCInfo_Shared, SurfSide2GlobalSide
USE MOD_Particle_Mesh_Vars      ,ONLY: SideInfo_Shared
#if USE_MPI
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars        ,ONLY: PerformLoadBalance
USE MOD_Particle_Mesh_Vars      ,ONLY: offsetComputeNodeElem
USE MOD_MPI_Shared_Vars         ,ONLY: myComputeNodeRank, nComputeNodeProcessors
USE MOD_MPI_Shared_Vars         ,ONLY: MPI_COMM_SHARED
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                           :: AdaptiveDataExists
REAL,ALLOCATABLE                  :: ElemData_HDF5(:,:,:)
INTEGER                           :: iElem, iSpec, iSF, iSide, ElemID, SampleElemID, nVar, GlobalSideID, GlobalElemID, currentBC
#if USE_MPI
INTEGER                           :: offsetElemCNProc(nComputeNodeProcessors), nSendCount(nComputeNodeProcessors)
REAL,ALLOCATABLE                  :: AdaptBCAverageTemp(:,:,:,:)
#endif /*USE_MPI*/
!===================================================================================================================================

AdaptBCSampleElemNum = 0
ALLOCATE(AdaptBCMapElemToSample(nElems))
AdaptBCMapElemToSample = 0

! 1) Count the number of sample elements and create mapping from ElemID to SampleElemID
! 1a) Add elements for the adaptive surface flux
DO iSpec=1,nSpecies
  DO iSF=1,Species(iSpec)%nSurfacefluxBCs
    currentBC = Species(iSpec)%Surfaceflux(iSF)%BC
    ! Skip processors without a surface flux
    IF (BCdata_auxSF(currentBC)%SideNumber.EQ.0) CYCLE
    ! Loop over sides on the surface flux
    DO iSide=1,BCdata_auxSF(currentBC)%SideNumber
      ElemID = SideToElem(S2E_ELEM_ID,BCdata_auxSF(currentBC)%SideList(iSide))
      IF (Species(iSpec)%Surfaceflux(iSF)%Adaptive) THEN
        ! Only add elements once
        IF(AdaptBCMapElemToSample(ElemID).NE.0) CYCLE
        ! Add the element to the BC sampling
        AdaptBCSampleElemNum = AdaptBCSampleElemNum + 1
        AdaptBCMapElemToSample(ElemID) = AdaptBCSampleElemNum
      END IF
    END DO
  END DO
END DO

! 1b) Add elements for the porous BCs
IF(nPorousBC.GT.0) THEN
  DO iSide = 1, nPorousSides
    GlobalSideID = SurfSide2GlobalSide(SURF_SIDEID,PorousBCInfo_Shared(2,iSide))
    GlobalElemID = SideInfo_Shared(SIDE_ELEMID,GlobalSideID)
    ! Only treat your proc-local elements
    IF ((GlobalElemID.LT.1+offSetElem).OR.(GlobalElemID.GT.nElems+offSetElem)) CYCLE
    ElemID = GlobalElemID - offsetElem
    ! Only add elements once
    IF(AdaptBCMapElemToSample(ElemID).NE.0) CYCLE
    ! Add the element to the BC sampling
    AdaptBCSampleElemNum = AdaptBCSampleElemNum + 1
    AdaptBCMapElemToSample(ElemID) = AdaptBCSampleElemNum
  END DO
END IF

! 2) Allocate the sampling arrays and create mapping from SampleElemID to ElemID
SampleElemID = 0
ALLOCATE(AdaptBCMapSampleToElem(AdaptBCSampleElemNum))
DO iElem = 1,nElems
  IF(AdaptBCMapElemToSample(iElem).NE.0) THEN
    SampleElemID = SampleElemID + 1
    AdaptBCMapSampleToElem(SampleElemID) = iElem
  END IF
END DO

ALLOCATE(AdaptBCMacroVal(1:7,1:AdaptBCSampleElemNum,1:nSpecies))
AdaptBCMacroVal(:,:,:) = 0.0
ALLOCATE(AdaptBCSample(1:8,1:AdaptBCSampleElemNum,1:nSpecies))
AdaptBCSample = 0.0

! 3) Read-in of the additional variables for sampling

AdaptBCRelaxFactor = GETREAL('AdaptiveBC-RelaxationFactor')
AdaptBCSampIter = GETINT('AdaptiveBC-SamplingIteration')
AdaptBCTruncAverage = GETLOGICAL('AdaptiveBC-TruncateRunningAverage')

! 3a) Initialize truncated average (and read-in of the sample array after a load balance step)
IF(AdaptBCTruncAverage) THEN
  IF(AdaptBCSampIter.EQ.0) THEN
    CALL abort(__STAMP__,&
      'ERROR: Truncated running average requires to the number of sampling iterations (AdaptiveBC-SamplingIteration > 0)!')
  END IF
  ALLOCATE(AdaptBCAverage(1:8,AdaptBCSampIter,1:AdaptBCSampleElemNum,1:nSpecies))
  AdaptBCAverage = 0.0
#if USE_MPI
#if USE_LOADBALANCE
  IF(PerformLoadBalance) THEN
    ALLOCATE(AdaptBCAverageTemp(1:8,AdaptBCSampIter,1:nElems,1:nSpecies))
    AdaptBCAverage = 0.0
    ! Displacement array (per proc)
    CALL MPI_GATHER(offsetElem,1,MPI_INTEGER_INT_KIND,offsetElemCNProc,1,MPI_INTEGER_INT_KIND,0,MPI_COMM_SHARED,iError)
    ! Send counter (per proc)
    CALL MPI_GATHER(8*AdaptBCSampIter*nElems*nSpecies,1,MPI_INTEGER_INT_KIND,nSendCount,1,MPI_INTEGER_INT_KIND,0,MPI_COMM_SHARED,iError)
    IF(myComputeNodeRank.EQ.0) THEN
      CALL MPI_SCATTERV(AdaptBCAverageGlobal,nSendCount,offsetElemCNProc,MPI_DOUBLE_PRECISION, &
                        AdaptBCAverageTemp,8*AdaptBCSampIter*nElems*nSpecies,MPI_DOUBLE_PRECISION,0,MPI_COMM_SHARED,IERROR)
    ELSE
      CALL MPI_SCATTERV(MPI_IN_PLACE,nSendCount,offsetElemCNProc,MPI_DOUBLE_PRECISION, &
                        AdaptBCAverageTemp,8*AdaptBCSampIter*nElems*nSpecies,MPI_DOUBLE_PRECISION, 0, MPI_COMM_SHARED,IERROR)
    END IF
    DO SampleElemID = 1,AdaptBCSampleElemNum
      ElemID = AdaptBCMapSampleToElem(SampleElemID)
      AdaptBCAverage(:,:,SampleElemID,:) = AdaptBCAverageTemp(:,:,ElemID,:)
    END DO
    DEALLOCATE(AdaptBCAverageTemp)
  END IF
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
END IF

! 4) If restart is done, check if adaptiveinfo exists in state, read it in and write to AdaptBCMacroValues
IF (DoRestart) THEN
  CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=MPI_COMM_WORLD)
  ! read local ParticleInfo from HDF5
  CALL DatasetExists(File_ID,'AdaptiveInfo',AdaptiveDataExists)
  IF(AdaptiveDataExists)THEN
    CALL GetDataSize(File_ID,'AdaptiveInfo',nDims,HSize)
    nVar=INT(HSize(1),4)
    DEALLOCATE(HSize)
    ALLOCATE(ElemData_HDF5(1:nVar,1:nSpecies,1:nElems))
    ! Associate construct for integer KIND=8 possibility
    ASSOCIATE (&
          nSpecies   => INT(nSpecies,IK) ,&
          offsetElem => INT(offsetElem,IK),&
          nElems     => INT(nElems,IK)    ,&
          nVar       => INT(nVar,IK)    )
      CALL ReadArray('AdaptiveInfo',3,(/nVar, nSpecies, nElems/),offsetElem,3,RealArray=ElemData_HDF5(:,:,:))
    END ASSOCIATE
    DO SampleElemID = 1,AdaptBCSampleElemNum
      ElemID = AdaptBCMapSampleToElem(SampleElemID)
      AdaptBCMacroVal(1:3,SampleElemID,:)   = ElemData_HDF5(1:3,:,ElemID)
      ! nVar-3 only due to backwards compatibility (old state files have a larger array of 10 variables)
      AdaptBCMacroVal(4,SampleElemID,:)     = ElemData_HDF5(nVar-3,:,ElemID)
      ! Porous BC parameter (5: Pumping capacity [m3/s], 6: Static pressure [Pa], 7: Integral pressure difference [Pa])
      AdaptBCMacroVal(5:7,SampleElemID,:)   = ElemData_HDF5(nVar-2:nVar,:,ElemID)
    END DO
    SDEALLOCATE(ElemData_HDF5)
  END IF
  CALL CloseDataFile()
END IF

! 5) If no values have been read-in, initialize the sample with values either the macroscopic restart or the surface flux

IF (AdaptiveDataExists) RETURN

IF (DoMacroscopicRestart) THEN
  DO SampleElemID = 1,AdaptBCSampleElemNum
    ElemID = AdaptBCMapSampleToElem(SampleElemID)
    AdaptBCMacroVal(DSMC_VELOX,SampleElemID,iSpec) = MacroRestartValues(ElemID,iSpec,DSMC_VELOX)
    AdaptBCMacroVal(DSMC_VELOY,SampleElemID,iSpec) = MacroRestartValues(ElemID,iSpec,DSMC_VELOY)
    AdaptBCMacroVal(DSMC_VELOZ,SampleElemID,iSpec) = MacroRestartValues(ElemID,iSpec,DSMC_VELOZ)
    AdaptBCMacroVal(4,SampleElemID,iSpec)          = MacroRestartValues(ElemID,iSpec,DSMC_NUMDENS)
  END DO
  IF(nPorousBC.GT.0) THEN
    CALL abort(__STAMP__,&
      'Macroscopic restart with porous BC and without state file including adaptive BC info not implemented!')
  END IF
ELSE
  DO iSpec=1,nSpecies
    DO iSF=1,Species(iSpec)%nSurfacefluxBCs
      currentBC = Species(iSpec)%Surfaceflux(iSF)%BC
      ! Skip processors without a surface flux
      IF (BCdata_auxSF(currentBC)%SideNumber.EQ.0) CYCLE
      ! Loop over sides on the surface flux
      DO iSide=1,BCdata_auxSF(currentBC)%SideNumber
        ElemID = SideToElem(S2E_ELEM_ID,BCdata_auxSF(currentBC)%SideList(iSide))
        SampleElemID = AdaptBCMapElemToSample(ElemID)
        AdaptBCMacroVal(1:3,SampleElemID,iSpec) = Species(iSpec)%Surfaceflux(iSF)%VeloIC*Species(iSpec)%Surfaceflux(iSF)%VeloVecIC(1:3)
        AdaptBCMacroVal(4,SampleElemID,iSpec) = Species(iSpec)%Surfaceflux(iSF)%PartDensity
      END DO
    END DO
  END DO
END IF

! sampling of near adaptive boundary element values in the first time step to get initial distribution for porous BC
IF(.NOT.DoRestart.AND..NOT.PerformLoadBalance) THEN
  CALL AdaptiveBCSampling(initSampling_opt=.TRUE.)
END IF

END SUBROUTINE InitAdaptiveBCSampling


SUBROUTINE AdaptiveBCSampling(initSampling_opt)
!===================================================================================================================================
! Sampling of variables (part-density and velocity) for adaptive BC and porous BC elements
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Sampling_Vars
USE MOD_DSMC_Analyze           ,ONLY: CalcTVibPoly,CalcTelec
USE MOD_DSMC_Vars              ,ONLY: PartStateIntEn, DSMC, SpecDSMC, useDSMC, RadialWeighting
USE MOD_Mesh_Vars              ,ONLY: nElems, offsetElem
USE MOD_Mesh_Tools             ,ONLY: GetCNElemID
USE MOD_Part_Tools             ,ONLY: GetParticleWeight
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemInfo_Shared, SideInfo_Shared
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemVolume_Shared
USE MOD_Particle_Vars          ,ONLY: PartState, PDM, PartSpecies, Species, nSpecies, PEM, usevMPF
USE MOD_Timedisc_Vars          ,ONLY: iter
USE MOD_SurfaceModel_Vars      ,ONLY: nPorousBC
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers     ,ONLY: LBStartTime, LBElemSplitTime, LBPauseTime
USE MOD_LoadBalance_vars       ,ONLY: nPartsPerBCElem
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
LOGICAL, INTENT(IN), OPTIONAL   :: initSampling_opt
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: ElemID, PartID, SampleElemID, iPart, iSpec, SamplingIteration, TruncIter
REAL                            :: partWeight, TTrans_TempFac, RelaxationFactor
LOGICAL                         :: initSampling, isBCElem, CalcValues
#if USE_LOADBALANCE
REAL                            :: tLBStart
#endif /*USE_LOADBALANCE*/
INTEGER                         :: nlocSides, GlobalSideID, CNElemID, GlobalElemID, iLocSide
!===================================================================================================================================

! Optional flag for the utilization of the routine for an initial sampling of the density and pressure distribution before simstart
IF(PRESENT(initSampling_opt)) THEN
  initSampling = initSampling_opt
ELSE
 initSampling = .FALSE.
END IF

CalcValues = .FALSE.

! If no particles are present during the initial sampling, leave the routine, otherwise initial variables for the
! adaptive inlet surface flux will be overwritten by zero's.
IF (PDM%ParticleVecLength.LT.1) RETURN

! Leave the routine if the processors does not have elements at an adaptive BC
IF (AdaptBCSampleElemNum.EQ.0) RETURN

! Calculate the counter for the truncated moving average
IF(AdaptBCTruncAverage) THEN
  TruncIter = MERGE(AdaptBCSampIter,MOD(INT(iter,4)+1,AdaptBCSampIter),MOD(INT(iter,4)+1,AdaptBCSampIter).EQ.0)
  ! Delete the oldest sample (required, otherwise it would be added to the new sample)
  AdaptBCAverage(1:8,TruncIter,1:AdaptBCSampleElemNum,1:nSpecies) = 0.
END IF

#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
DO SampleElemID = 1,AdaptBCSampleElemNum
  ElemID = AdaptBCMapSampleToElem(SampleElemID)
  PartID = PEM%pStart(ElemID)
#if USE_LOADBALANCE
  nPartsPerBCElem(ElemID) = nPartsPerBCElem(ElemID) + PEM%pNumber(ElemID)
#endif /*USE_LOADBALANCE*/
  DO iPart = 1,PEM%pNumber(ElemID)
    ! Sample the particle properties
    iSpec = PartSpecies(PartID)
    partWeight = GetParticleWeight(PartID)
    IF(AdaptBCTruncAverage) THEN
      ! Store the samples of the last AdaptBCSampIter and replace the oldest with the newest sample
      AdaptBCAverage(1:3,TruncIter,SampleElemID, iSpec) = AdaptBCAverage(1:3,TruncIter,SampleElemID,iSpec) + PartState(4:6,PartID) * partWeight
      IF(nPorousBC.GT.0) THEN
        AdaptBCAverage(4:6,TruncIter,SampleElemID, iSpec) = AdaptBCAverage(4:6,TruncIter,SampleElemID,iSpec) + PartState(4:6,PartID)**2 * partWeight
      END IF
      AdaptBCAverage(7,  TruncIter,SampleElemID, iSpec) = AdaptBCAverage(7,  TruncIter,SampleElemID,iSpec) + 1.0  ! simulation particle number
      AdaptBCAverage(8,  TruncIter,SampleElemID, iSpec) = AdaptBCAverage(8,  TruncIter,SampleElemID,iSpec) + partWeight
    ELSE
      AdaptBCSample(1:3,SampleElemID, iSpec) = AdaptBCSample(1:3,SampleElemID,iSpec) + PartState(4:6,PartID) * partWeight
      IF(nPorousBC.GT.0) THEN
        AdaptBCSample(4:6,SampleElemID, iSpec) = AdaptBCSample(4:6,SampleElemID,iSpec) + PartState(4:6,PartID)**2 * partWeight
      END IF
      AdaptBCSample(7,SampleElemID, iSpec) = AdaptBCSample(7,SampleElemID, iSpec) + 1.0  ! simulation particle number
      AdaptBCSample(8,SampleElemID, iSpec) = AdaptBCSample(8,SampleElemID, iSpec) + partWeight
    END IF
    PartID = PEM%pNext(PartID)
  END DO
END DO
#if USE_LOADBALANCE
CALL LBPauseTime(LB_ADAPTIVE,tLBStart)
#endif /*USE_LOADBALANCE*/

IF(initSampling) THEN
  RelaxationFactor = 1
  SamplingIteration = 1
  CalcValues = .TRUE.
ELSE
  RelaxationFactor = AdaptBCRelaxFactor
  IF(AdaptBCSampIter.GT.0) THEN
    IF(AdaptBCTruncAverage.AND.(iter+1_8.LT.INT(AdaptBCSampIter,8))) THEN
      ! Truncated average: get the correct number of samples to calculate the average number density while the 
      ! sampling array is populated
      SamplingIteration = INT(iter,4) + 1
    ELSE
      SamplingIteration = AdaptBCSampIter
    END IF
    ! Determine whether the macroscopic values shall be calculated from the sample (e.g. every 100 steps)
    CalcValues = MOD(iter+1_8,INT(SamplingIteration,8)).EQ.0_8
  END IF
END IF

IF(AdaptBCTruncAverage) THEN
  ! Sum-up the complete sample over the number of sampling iterations
  AdaptBCSample(1:8,1:AdaptBCSampleElemNum,1:nSpecies) = SUM(AdaptBCAverage(1:8,:,1:AdaptBCSampleElemNum,1:nSpecies),2)
END IF

DO SampleElemID = 1,AdaptBCSampleElemNum
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ElemID = AdaptBCMapSampleToElem(SampleElemID)
  CNElemID = GetCNElemID(ElemID+offsetElem)
  DO iSpec = 1,nSpecies
    IF(AdaptBCSampIter.GT.0) THEN
      ! ================================================================
      ! Sampling iteration: sampling for AdaptBCSampIter iterations, calculating the macro values and resetting sample OR
      ! AdaptBCTruncAverage: continuous average of the last AdaptBCSampIter iterations
      IF(CalcValues.OR.AdaptBCTruncAverage) THEN
        IF (AdaptBCSample(7,SampleElemID,iSpec).GT.0.0) THEN
          ! Calculate the average velocties
          AdaptBCSample(1:6,SampleElemID,iSpec) = AdaptBCSample(1:6,SampleElemID,iSpec) / AdaptBCSample(8,SampleElemID,iSpec)
          IF(.NOT.initSampling) THEN
            ! Compute flow velocity (during computation, not for the initial distribution, where the velocity from the ini is used)
            AdaptBCMacroVal(1:3,SampleElemID,iSpec) = AdaptBCSample(1:3,SampleElemID, iSpec)
          END IF
          ! number density
          IF(usevMPF.OR.RadialWeighting%DoRadialWeighting) THEN
            AdaptBCMacroVal(4,SampleElemID,iSpec) = AdaptBCSample(8,SampleElemID,iSpec) / REAL(SamplingIteration) / ElemVolume_Shared(CNElemID)
          ELSE
            AdaptBCMacroVal(4,SampleElemID,iSpec) = AdaptBCSample(8,SampleElemID,iSpec) / REAL(SamplingIteration) / ElemVolume_Shared(CNElemID) &
                                              * Species(iSpec)%MacroParticleFactor
          END IF
          ! pressure (only for porous BC)
          IF(nPorousBC.GT.0) THEN
            IF(AdaptBCSample(7,SampleElemID,iSpec).GT.1) THEN
              ! instantaneous temperature WITHOUT 1/BoltzmannConst
              TTrans_TempFac = (AdaptBCSample(7,SampleElemID,iSpec)/(AdaptBCSample(7,SampleElemID,iSpec)-1.0)) &
                  *Species(iSpec)%MassIC*(AdaptBCSample(4,SampleElemID,iSpec) - AdaptBCSample(1,SampleElemID,iSpec)**2   &
                                        + AdaptBCSample(5,SampleElemID,iSpec) - AdaptBCSample(2,SampleElemID,iSpec)**2   &
                                        + AdaptBCSample(6,SampleElemID,iSpec) - AdaptBCSample(3,SampleElemID,iSpec)**2) / 3.
              ! pressure (BoltzmannConstant canceled out in temperature calculation)
              AdaptBCMacroVal(6,SampleElemID,iSpec)=AdaptBCMacroVal(4,SampleElemID,iSpec)*TTrans_TempFac
            END IF
          END IF  ! nPorousBC.GT.0
        END IF    ! AdaptBCSample(7,SampleElemID,iSpec).GT.0.0
        ! Resetting sampled values
        AdaptBCSample(1:8,SampleElemID,iSpec) = 0.
      END IF  ! CalcValues.OR.AdaptBCTruncAverage
    ELSE  ! AdaptBCSampIter.LE.0
      ! ================================================================
      ! Relaxation factor: updating the macro values with a certain percentage of the current sampled value
      IF (AdaptBCSample(7,SampleElemID,iSpec).GT.0.0) THEN
        ! Calculate the average velocties
        AdaptBCSample(1:6,SampleElemID,iSpec) = AdaptBCSample(1:6,SampleElemID,iSpec) / AdaptBCSample(8,SampleElemID,iSpec)
        IF(.NOT.initSampling) THEN
          ! compute flow velocity (during computation, not for the initial distribution, where the velocity from the ini is used)
          AdaptBCMacroVal(1:3,SampleElemID,iSpec) = (1-RelaxationFactor)*AdaptBCMacroVal(1:3,SampleElemID,iSpec) &
                                              + RelaxationFactor*AdaptBCSample(1:3,SampleElemID, iSpec)
        END IF
        ! Calculation of the number density
        IF(usevMPF.OR.RadialWeighting%DoRadialWeighting) THEN
          AdaptBCMacroVal(4,SampleElemID,iSpec) = (1-RelaxationFactor)*AdaptBCMacroVal(4,SampleElemID,iSpec) &
            + RelaxationFactor*AdaptBCSample(8,SampleElemID,iSpec) / ElemVolume_Shared(CNElemID)
        ELSE
          AdaptBCMacroVal(4,SampleElemID,iSpec) = (1-RelaxationFactor)*AdaptBCMacroVal(4,SampleElemID,iSpec) &
            + RelaxationFactor*AdaptBCSample(8,SampleElemID,iSpec) / ElemVolume_Shared(CNElemID)*Species(iSpec)%MacroParticleFactor
        END IF
        ! pressure (only for porous BC)
        IF(nPorousBC.GT.0) THEN
          ! Compute instantaneous temperature WITHOUT 1/BoltzmannConst
          IF (AdaptBCSample(7,SampleElemID,iSpec).GT.1.0) THEN
            TTrans_TempFac = (AdaptBCSample(7,SampleElemID,iSpec)/(AdaptBCSample(7,SampleElemID,iSpec)-1.0)) &
                              * Species(iSpec)%MassIC * (AdaptBCSample(4,SampleElemID,iSpec) - AdaptBCSample(1,SampleElemID,iSpec)**2 &
                                                       + AdaptBCSample(5,SampleElemID,iSpec) - AdaptBCSample(2,SampleElemID,iSpec)**2 &
                                                       + AdaptBCSample(6,SampleElemID,iSpec) - AdaptBCSample(3,SampleElemID,iSpec)**2) / 3.
            AdaptBCMacroVal(6,SampleElemID,iSpec) = (1-RelaxationFactor)*AdaptBCMacroVal(6,SampleElemID,iSpec) &
                                              + RelaxationFactor*AdaptBCMacroVal(4,SampleElemID,iSpec)*TTrans_TempFac
          END IF
        END IF
      ELSE
        ! Relax the values towards zero
        AdaptBCMacroVal(1:7,SampleElemID,iSpec) = (1-RelaxationFactor)*AdaptBCMacroVal(1:7,SampleElemID,iSpec)
      END IF  ! AdaptBCSample(7,SampleElemID,iSpec).GT.0.0
      ! Resetting sampled values
      AdaptBCSample(1:8,SampleElemID,iSpec) = 0.
    END IF    ! AdaptBCSampIter.GT.0
  END DO      ! iSpec = 1,nSpecies
#if USE_LOADBALANCE
  CALL LBElemSplitTime(ElemID,tLBStart)
#endif /*USE_LOADBALANCE*/
END DO        ! SampleElemID = 1,AdaptBCSampleElemNum

END SUBROUTINE AdaptiveBCSampling


SUBROUTINE FinalizeParticleSamplingAdaptive(IsLoadBalance)
!----------------------------------------------------------------------------------------------------------------------------------!
!>
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Particle_Sampling_Vars
USE MOD_Particle_Vars           ,ONLY: nSpecies
#if USE_MPI
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars        ,ONLY: PerformLoadBalance
USE MOD_Mesh_Vars               ,ONLY: offsetElem, nElems, nGlobalElems
USE MOD_Particle_Mesh_Vars      ,ONLY: nComputeNodeElems,offsetComputeNodeElem
USE MOD_MPI_Shared_Vars         ,ONLY: myComputeNodeRank, nComputeNodeProcessors, nProcessors_Global
USE MOD_MPI_Shared_Vars         ,ONLY: MPI_COMM_SHARED, MPI_COMM_LEADERS_SHARED
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
LOGICAL                         :: IsLoadBalance
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: ElemID, SampleElemID, offsetElemProc(nComputeNodeProcessors), nRecvCount(nComputeNodeProcessors)
REAL                            :: AdaptBCAverageTempProc(1:8,1:AdaptBCSampIter,1:nElems,1:nSpecies)
REAL,ALLOCATABLE                :: AdaptBCAverageTempCN(:,:,:,:), AdaptBCAverageTempGlobal(:,:,:,:)
!===================================================================================================================================
#if USE_MPI
#if USE_LOADBALANCE
IF(AdaptBCTruncAverage) THEN
  IF(IsLoadBalance) THEN
    ! IF(.NOT.ALLOCATED(AdaptBCAverageGlobal)) THEN
    !   ALLOCATE(AdaptBCAverageGlobal(1:8,1:AdaptBCSampIter,1:nGlobalElems,1:nSpecies))
    !   AdaptBCAverageGlobal = 0.
    ! END IF
    ! DO SampleElemID = 1,AdaptBCSampleElemNum
    !   ElemID = AdaptBCMapSampleToElem(SampleElemID)
    !   AdaptBCAverageGlobal(:,:,offsetElem+ElemID,:) = AdaptBCAverage(:,:,SampleElemID,:)
    ! END DO
    ! CALL MPI_ALLREDUCE(MPI_IN_PLACE,AdaptBCAverageGlobal,8*AdaptBCSampIter*nGlobalElems*nSpecies,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_SHARED,IERROR)
    ! ########################################################################
    AdaptBCAverageTempProc = 0.
    ! Store the sampled values in a nElems array
    DO SampleElemID = 1,AdaptBCSampleElemNum
      ElemID = AdaptBCMapSampleToElem(SampleElemID)
      AdaptBCAverageTempProc(:,:,ElemID,:) = AdaptBCAverage(:,:,SampleElemID,:)
    END DO
    ! Compute-node leader gathers the information from his node processors
    ! Displacement array (per proc)
    CALL MPI_GATHER(offsetElem,1,MPI_INTEGER_INT_KIND,offsetElemProc,1,MPI_INTEGER_INT_KIND,0,MPI_COMM_SHARED,iError)
    ! Receive counter (per proc)
    CALL MPI_GATHER(8*AdaptBCSampIter*nElems*nSpecies,1,MPI_INTEGER_INT_KIND,nRecvCount,1,MPI_INTEGER_INT_KIND,0,MPI_COMM_SHARED,iError)
    ! Compute-node leaders get the complete array
    IF (myComputeNodeRank.EQ.0) THEN
      IF(.NOT.ALLOCATED(AdaptBCAverageGlobal)) THEN
        ALLOCATE(AdaptBCAverageGlobal(1:8,1:AdaptBCSampIter,1:nGlobalElems,1:nSpecies))
      END IF
      AdaptBCAverageGlobal = 0.
      CALL MPI_GATHERV(AdaptBCAverageTempProc,8*AdaptBCSampIter*nElems*nSpecies,MPI_DOUBLE_PRECISION, &
                      AdaptBCAverageGlobal, nRecvCount, offsetElemProc, MPI_DOUBLE_PRECISION, 0, MPI_COMM_SHARED,IERROR)
      ! All-reduce between node leaders (in case of multi-node)
      IF (nComputeNodeProcessors.LT.nProcessors_Global) &
        CALL MPI_ALLREDUCE(MPI_IN_PLACE,AdaptBCAverageGlobal,1,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_LEADERS_SHARED,IERROR)
    ELSE
      CALL MPI_GATHERV(AdaptBCAverageTempProc,8*AdaptBCSampIter*nElems*nSpecies,MPI_DOUBLE_PRECISION, &
                      MPI_IN_PLACE, nRecvCount, offsetElemProc, MPI_DOUBLE_PRECISION, 0, MPI_COMM_SHARED,IERROR)
    END IF
  ELSE
    SDEALLOCATE(AdaptBCAverageGlobal)
  END IF
END IF
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
SDEALLOCATE(AdaptBCAverage)
SDEALLOCATE(AdaptBCMacroVal)
SDEALLOCATE(AdaptBCSample)
SDEALLOCATE(AdaptBCMapSampleToElem)
SDEALLOCATE(AdaptBCMapElemToSample)

END SUBROUTINE FinalizeParticleSamplingAdaptive

END MODULE MOD_Particle_Sampling_Adapt