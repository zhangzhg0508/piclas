!==================================================================================================================================
! Copyright (c) 2018 - 2019 Marcel Pfeiffer
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
MODULE MOD_BGK_Vars
!===================================================================================================================================
!> description
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
LOGICAL                                        :: BGKInitDone = .FALSE.

TYPE tSpeciesBGK                                                              ! ESBK Species Param
  REAL, ALLOCATABLE                            :: CollFreqPreFactor(:)
END TYPE tSpeciesBGK

TYPE(tSpeciesBGK), ALLOCATABLE                 :: SpecBGK(:)                  ! Species DSMC params (nSpec)
LOGICAL                                        :: DoBGKCellAdaptation
INTEGER                                        :: BGKCollModel                  ! 1 ES-BGK; 2 S-BGK; 3 BGK; 4 Unified
INTEGER                                        :: ESBGKModel                    ! 1 Approx Levin; 2 Exact Solution A; 3 Metropolis
REAL                                           :: BGKUnifiedCes
INTEGER                                        :: BGKMinPartPerCell
LOGICAL                                        :: BGKMovingAverage
INTEGER                                        :: BGKMovingAverageLength
LOGICAL                                        :: BGKUseQuantVibEn
INTEGER                                        :: SBGKEnergyConsMethod
LOGICAL                                        :: BGKDoVibRelaxation
REAL                                           :: BGKSplittingDens
REAL                                           :: BGKDSMCSwitchDens
LOGICAL                                        :: CoupledBGKDSMC
REAL, ALLOCATABLE                              :: BGK_QualityFacSamp(:,:)
INTEGER                                        :: BGK_MeanRelaxFactorCounter
REAL                                           :: BGK_MeanRelaxFactor
REAL                                           :: BGK_MaxRelaxFactor
REAL                                           :: BGK_MaxRotRelaxFactor
REAL                                           :: BGK_PrandtlNumber
REAL                                           :: BGK_ExpectedPrandtlNumber

TYPE tElemNodeAveraging
    TYPE (tNodeAverage), POINTER               :: Root => null()
END TYPE

TYPE tNodeAverage
    TYPE (tNodeAverage), POINTER               :: SubNode1 => null()
    TYPE (tNodeAverage), POINTER               :: SubNode2 => null()
    TYPE (tNodeAverage), POINTER               :: SubNode3 => null()
    TYPE (tNodeAverage), POINTER               :: SubNode4 => null()
    TYPE (tNodeAverage), POINTER               :: SubNode5 => null()
    TYPE (tNodeAverage), POINTER               :: SubNode6 => null()
    TYPE (tNodeAverage), POINTER               :: SubNode7 => null()
    TYPE (tNodeAverage), POINTER               :: SubNode8 => null()
    REAL, ALLOCATABLE                          :: AverageValues(:,:)
    INTEGER                                    :: CorrectStep
END TYPE

TYPE (tElemNodeAveraging), ALLOCATABLE         :: ElemNodeAveraging(:)
!===================================================================================================================================
END MODULE MOD_BGK_Vars
