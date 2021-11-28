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

MODULE MOD_MCC_Init
!===================================================================================================================================
!> Initialization of the Monte Carlo Collision module
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

PUBLIC :: DefineParametersMCC, MCC_Init, MCC_Chemistry_Init, FinalizeMCC
!===================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Define parameters for MCC
!==================================================================================================================================
SUBROUTINE DefineParametersMCC()
! MODULES
USE MOD_Globals
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection("MCC")

CALL prms%CreateStringOption(   'Particles-CollXSec-Database', 'File name for the collision cross section database. Container '//&
                                                               'should be named with species pair (e.g. "Ar-electron"). The '//&
                                                               'first column shall contain the energy in eV and the second '//&
                                                               'column the cross-section in m^2', 'none')
CALL prms%CreateLogicalOption(  'Particles-CollXSec-NullCollision'  &
                                  ,'Utilize the null collision method for the determination of the number of pairs '//&
                                  'based on the maximum collision frequency and time step (only with a background gas)' &
                                  ,'.TRUE.')

END SUBROUTINE DefineParametersMCC


SUBROUTINE MCC_Init()
!===================================================================================================================================
!> Read-in of the collision and vibrational cross-section database and initialization of the null collision method.
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_Globals_Vars  ,ONLY: ElementaryCharge
USE MOD_PARTICLE_Vars ,ONLY: nSpecies
USE MOD_DSMC_Vars     ,ONLY: BGGas, SpecDSMC, CollInf, DSMC
USE MOD_MCC_Vars      ,ONLY: XSec_Database, SpecXSec, XSec_NullCollision, XSec_Relaxation
USE MOD_MCC_XSec      ,ONLY: ReadCollXSec, ReadVibXSec, InterpolateCrossSection_Vib, ReadElecXSec, InterpolateCrossSection_Elec
#if defined(PARTICLES) && USE_HDG
USE MOD_HDG_Vars      ,ONLY: UseBRElectronFluid,BRNullCollisionDefault
USE MOD_ReadInTools   ,ONLY: PrintOption
#endif /*defined(PARTICLES) && USE_HDG*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER       :: iSpec, jSpec, iCase, partSpec
REAL          :: TotalProb(nSpecies), CrossSection
INTEGER       :: iLevel, nVib, iStep, MaxDim
!===================================================================================================================================

XSec_Database = TRIM(GETSTR('Particles-CollXSec-Database'))
IF(BGGas%NumberOfSpecies.GT.0) THEN
  XSec_NullCollision = GETLOGICAL('Particles-CollXSec-NullCollision')
ELSE
  XSec_NullCollision = .FALSE.
END IF
XSec_Relaxation = .FALSE.

IF(TRIM(XSec_Database).EQ.'none') THEN
  CALL abort(&
  __STAMP__&
  ,'ERROR: No database for the collision cross-section given!')
END IF

ALLOCATE(SpecXSec(CollInf%NumCase))
SpecXSec(:)%UseCollXSec = .FALSE.
SpecXSec(:)%UseVibXSec = .FALSE.
SpecXSec(:)%UseElecXSec = .FALSE.
SpecXSec(:)%CollXSec_Effective = .FALSE.
SpecXSec(:)%SpeciesToRelax = 0
TotalProb = 0.

DO iSpec = 1, nSpecies
  DO jSpec = iSpec, nSpecies
    iCase = CollInf%Coll_Case(iSpec,jSpec)
    ! Skip species, which shall not be treated with collision cross-sections
    IF(.NOT.SpecDSMC(iSpec)%UseCollXSec.AND..NOT.SpecDSMC(jSpec)%UseCollXSec.AND. &
       .NOT.SpecDSMC(iSpec)%UseVibXSec.AND..NOT.SpecDSMC(jSpec)%UseVibXSec) CYCLE
    ! Skip pairing with itself and pairing with other particle species, if background gas is active
    IF(BGGas%NumberOfSpecies.GT.0) THEN
      IF(iSpec.EQ.jSpec) CYCLE
      IF(.NOT.BGGas%BackgroundSpecies(iSpec).AND..NOT.BGGas%BackgroundSpecies(jSpec)) CYCLE
    END IF
    ! Read-in cross-section data for collisions of particles, allocating CollXSecData within the following routine
    IF(SpecDSMC(iSpec)%UseCollXSec.OR.SpecDSMC(jSpec)%UseCollXSec) CALL ReadCollXSec(iCase, iSpec, jSpec)
    ! Check if both species were given the UseCollXSec flag and store the energy value in Joule
    IF(SpecXSec(iCase)%UseCollXSec) THEN
      IF(SpecDSMC(iSpec)%UseCollXSec.AND.SpecDSMC(jSpec)%UseCollXSec) THEN
        CALL abort(&
          __STAMP__&
          ,'ERROR: Both species defined to use collisional cross-section, define only the source species with UseCollXSec!')
      END IF
      ! Store the energy value in J (read-in was in eV)
      SpecXSec(iCase)%CollXSecData(1,:) = SpecXSec(iCase)%CollXSecData(1,:) * ElementaryCharge
    END IF
    ! Read-in vibrational cross sections
    IF(SpecDSMC(iSpec)%UseVibXSec.OR.SpecDSMC(jSpec)%UseVibXSec) CALL ReadVibXSec(iCase, iSpec, jSpec)
    ! Vibrational relaxation probabilities: Interpolate and store the probability at the collision cross-section levels
    IF(SpecXSec(iCase)%UseVibXSec) THEN
      IF(SpecDSMC(iSpec)%UseVibXSec.AND.SpecDSMC(jSpec)%UseVibXSec) THEN
        CALL abort(&
          __STAMP__&
          ,'ERROR: Both species defined to use vib. cross-section, define only the source species with UseVibXSec!')
      END IF
      ! Save which species shall use the vibrational cross-section data for relaxation probabilities
      ! If the species which was given the UseVibXSec flag is diatomic/polyatomic, use the cross-section for that species
      ! If the species is an atom/electron, use the cross-section for the other collision partner (the background species)
      IF(SpecDSMC(iSpec)%UseVibXSec) THEN
        IF((SpecDSMC(iSpec)%InterID.EQ.2).OR.(SpecDSMC(iSpec)%InterID.EQ.20)) THEN
          SpecXSec(iCase)%SpeciesToRelax = iSpec
        ELSE
          SpecXSec(iCase)%SpeciesToRelax = jSpec
        END IF
      ELSE
        IF((SpecDSMC(jSpec)%InterID.EQ.2).OR.(SpecDSMC(jSpec)%InterID.EQ.20)) THEN
          SpecXSec(iCase)%SpeciesToRelax = jSpec
        ELSE
          SpecXSec(iCase)%SpeciesToRelax = iSpec
        END IF
      END IF
      XSec_Relaxation = .TRUE.
      nVib = SIZE(SpecXSec(iCase)%VibMode)
      DO iLevel = 1, nVib
        ! Store the energy value in J (read-in was in eV)
        SpecXSec(iCase)%VibMode(iLevel)%XSecData(1,:) = SpecXSec(iCase)%VibMode(iLevel)%XSecData(1,:) * ElementaryCharge
        SpecXSec(iCase)%VibMode(iLevel)%Threshold = SpecXSec(iCase)%VibMode(iLevel)%Threshold * ElementaryCharge
      END DO
      IF(SpecXSec(iCase)%UseCollXSec) THEN
        ! Collision cross-sections are available
        MaxDim = SIZE(SpecXSec(iCase)%CollXSecData,2)
        ALLOCATE(SpecXSec(iCase)%VibXSecData(1:2,1:MaxDim))
        ! Using the same energy intervals as for the collision cross-sections
        SpecXSec(iCase)%VibXSecData(1,:) = SpecXSec(iCase)%CollXSecData(1,:)
        SpecXSec(iCase)%VibXSecData(2,:) = 0.
        ! Interpolate the vibrational cross section at the energy levels of the collision collision cross section and sum-up the
        ! vibrational probability (vibrational cross-section divided by the effective)
        DO iStep = 1, MaxDim
          DO iLevel = 1, nVib
            CrossSection = InterpolateCrossSection_Vib(iCase,iLevel,SpecXSec(iCase)%CollXSecData(1,iStep))
            SpecXSec(iCase)%VibXSecData(2,iStep) = SpecXSec(iCase)%VibXSecData(2,iStep) + CrossSection
            ! When no effective cross-section is available, the vibrational cross-section has to be added to the collisional
            IF(SpecXSec(iCase)%CollXSec_Effective) THEN
              IF(CrossSection.GT.SpecXSec(iCase)%CollXSecData(2,iStep)) THEN
                SWRITE(*,*) 'Current vibrational energy level [eV]: ', SpecXSec(iCase)%VibMode(iLevel)%Threshold / ElementaryCharge
                SWRITE(*,*) 'Vibrational cross-section: ', CrossSection
                SWRITE(*,*) 'Effective cross-section: ', SpecXSec(iCase)%CollXSecData(2,iStep)
                SWRITE(*,*) 'Effective cross-section should be greater as the vibrational is supposed to be part of the effective cross-section.'
                SWRITE(*,*) 'Check the last value of the vibrational data, the cross-section should be zero, otherwise the last value will be taken for energies outside the vibrational data.'
                CALL abort(__STAMP__,'ERROR: Effective cross-section is smaller than the interpolated vibrational level cross-section!')
              END IF
            ELSE
              SpecXSec(iCase)%CollXSecData(2,iStep) = SpecXSec(iCase)%CollXSecData(2,iStep) + CrossSection
            END IF
          END DO
        END DO
      END IF    ! SpecXSec(iCase)%UseCollXSec
    END IF      ! SpecXSec(iCase)%UseVibXSec
    ! Read-in electronic cross-section data
    IF(DSMC%ElectronicModel.EQ.3) THEN
      CALL ReadElecXSec(iCase, iSpec, jSpec)
      IF(SpecXSec(iCase)%UseElecXSec) THEN
        DO iLevel = 1, SpecXSec(iCase)%NumElecLevel
          ! Store the energy value in J (read-in was in eV)
          SpecXSec(iCase)%ElecLevel(iLevel)%XSecData(1,:) = SpecXSec(iCase)%ElecLevel(iLevel)%XSecData(1,:) * ElementaryCharge
          SpecXSec(iCase)%ElecLevel(iLevel)%Threshold = SpecXSec(iCase)%ElecLevel(iLevel)%Threshold * ElementaryCharge
        END DO
        IF(SpecXSec(iCase)%UseCollXSec) THEN
          IF((SpecDSMC(iSpec)%InterID.NE.4).AND.(SpecDSMC(jSpec)%InterID.NE.4)) THEN
            ! Special treatment required if both collision partners have electronic energy levels (ie. one is not an electron)
            CALL abort(__STAMP__,'ERROR: Electronic relaxation with cross-section is only possible for electron collisions!')
          END IF
          ! Collision cross-sections are available
          MaxDim = SIZE(SpecXSec(iCase)%CollXSecData,2)
          ALLOCATE(SpecXSec(iCase)%ElecXSecData(1:2,1:MaxDim))
          ! Using the same energy intervals as for the collision cross-sections
          SpecXSec(iCase)%ElecXSecData(1,:) = SpecXSec(iCase)%CollXSecData(1,:)
          SpecXSec(iCase)%ElecXSecData(2,:) = 0.
          ! Interpolate the vibrational cross section at the energy levels of the collision collision cross section and sum-up the
          ! vibrational probability (vibrational cross-section divided by the effective)
          DO iStep = 1, MaxDim
            DO iLevel = 1, SpecXSec(iCase)%NumElecLevel
              CrossSection = InterpolateCrossSection_Elec(iCase,iLevel,SpecXSec(iCase)%CollXSecData(1,iStep))
              SpecXSec(iCase)%ElecXSecData(2,iStep) = SpecXSec(iCase)%ElecXSecData(2,iStep) + CrossSection
              ! When no effective cross-section is available, the vibrational cross-section has to be added to the collisional
              IF(SpecXSec(iCase)%CollXSec_Effective) THEN
                IF(CrossSection.GT.SpecXSec(iCase)%CollXSecData(2,iStep)) THEN
                  SWRITE(*,*) 'Current electronic energy level [eV]: ', SpecXSec(iCase)%ElecLevel(iLevel)%Threshold / ElementaryCharge
                  SWRITE(*,*) 'Electronic cross-section: ', CrossSection
                  SWRITE(*,*) 'Effective cross-section: ', SpecXSec(iCase)%CollXSecData(2,iStep)
                  SWRITE(*,*) 'Effective cross-section should be greater as the electronic is supposed to be part of the effective cross-section.'
                  SWRITE(*,*) 'Check the last value of the electronic data, it should be zero, otherwise the last value will be taken for energies outside the electronic data.'
                  CALL abort(__STAMP__,'ERROR: Effective cross-section is smaller than the interpolated electronic level cross-section!')
                END IF
              ELSE
                SpecXSec(iCase)%CollXSecData(2,iStep) = SpecXSec(iCase)%CollXSecData(2,iStep) + CrossSection
              END IF
            END DO
          END DO
        END IF    ! SpecXSec(iCase)%UseCollXSec
      END IF      ! SpecXSec(iCase)%UseElecXSec
    END IF
    ! Determine the maximum collision frequency for the null collision method
    IF(SpecXSec(iCase)%UseCollXSec) THEN
      IF(XSec_NullCollision) THEN
        CALL DetermineNullCollProb(iCase,iSpec,jSpec)
        ! Select the particle species in order to sum-up the total null collision probability per particle species
        IF(BGGas%BackgroundSpecies(iSpec)) THEN
          partSpec = jSpec
        ELSE
          partSpec = iSpec
        END IF
        TotalProb(partSpec) = TotalProb(partSpec) + SpecXSec(iCase)%ProbNull
        ! Sum of null collision probability per particle species should be lower than 1, otherwise not enough collision pairs
        IF(TotalProb(partSpec).GT.1.0) THEN
          CALL abort(__STAMP__&
          ,'ERROR: Total null collision probability is above unity. Please reduce the time step! Probability is: '&
          ,RealInfoOpt=TotalProb(partSpec))
        ELSEIF(TotalProb(partSpec).GT.0.1) THEN
          SWRITE(*,*) 'Total null collision probability is above 0.1. A value of 1E-2 is recommended in literature!'
          SWRITE(*,*) 'Particle Species: ', TRIM(SpecDSMC(partSpec)%Name), ' Probability: ', TotalProb(partSpec)
        END IF
      END IF
    END IF
  END DO        ! jSpec = iSpec, nSpecies
END DO          ! iSpec = 1, nSpecies

#if defined(PARTICLES) && USE_HDG
BRNullCollisionDefault = XSec_NullCollision ! Backup read-in parameter value (for switching null collision on/off)
IF(XSec_NullCollision.AND.UseBRElectronFluid)THEN
  XSec_NullCollision = .FALSE. ! Deactivate null collision when using BR electrons due to (possibly) increased time step
  CALL PrintOption('Using BR electron fuild model: Particles-CollXSec-NullCollision','INFO',LogOpt=XSec_NullCollision)
END IF
#endif /*defined(PARTICLES) && USE_HDG*/

END SUBROUTINE MCC_Init


SUBROUTINE DetermineNullCollProb(iCase,iSpec,jSpec)
!===================================================================================================================================
!> Routine for the MCC method: calculates the maximal collision frequency for a given species and the collision probability
!===================================================================================================================================
! MODULES
USE MOD_ReadInTools
USE MOD_Globals_Vars          ,ONLY: Pi
USE MOD_Particle_Vars         ,ONLY: Species
USE MOD_TimeDisc_Vars         ,ONLY: ManualTimeStep
USE MOD_DSMC_Vars             ,ONLY: BGGas
USE MOD_MCC_Vars              ,ONLY: SpecXSec
IMPLICIT NONE
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER,INTENT(IN)            :: iCase                            !< Case index
INTEGER,INTENT(IN)            :: iSpec
INTEGER,INTENT(IN)            :: jSpec
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                       :: MaxDOF, bggSpec
REAL                          :: MaxCollFreq, Mass
REAL,ALLOCATABLE              :: Velocity(:)
!===================================================================================================================================

! Select the background species as the target cloud and use the mass of particle species
IF(BGGas%BackgroundSpecies(iSpec)) THEN
  bggSpec = BGGas%MapSpecToBGSpec(iSpec)
  Mass = Species(jSpec)%MassIC
ELSE
  bggSpec = BGGas%MapSpecToBGSpec(jSpec)
  Mass = Species(iSpec)%MassIC
END IF

MaxDOF = SIZE(SpecXSec(iCase)%CollXSecData,2)
ALLOCATE(Velocity(MaxDOF))

! Determine the mean relative velocity at the given energy level
Velocity(1:MaxDOF) = SQRT(2.) * SQRT(8.*SpecXSec(iCase)%CollXSecData(1,1:MaxDOF)/(Pi*Mass))

! Calculate the maximal collision frequency
MaxCollFreq = MAXVAL(Velocity(1:MaxDOF) * SpecXSec(iCase)%CollXSecData(2,1:MaxDOF) * BGGas%NumberDensity(bggSpec))

! Determine the collision probability
SpecXSec(iCase)%ProbNull = 1. - EXP(-MaxCollFreq*ManualTimeStep)

DEALLOCATE(Velocity)

END SUBROUTINE DetermineNullCollProb


SUBROUTINE MCC_Chemistry_Init()
!===================================================================================================================================
!> Read-in of the reaction cross-section database and re-calculation of the null collision probability
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_MCC_XSec      ,ONLY: ReadReacXSec, InterpolateCrossSection_Chem
USE MOD_PARTICLE_Vars ,ONLY: nSpecies
USE MOD_DSMC_Vars     ,ONLY: BGGas, CollInf, ChemReac
USE MOD_MCC_Vars      ,ONLY: SpecXSec, XSec_NullCollision
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iSpec, jSpec, iCase, iReac
REAL                  :: TotalProb, ReactionCrossSection
INTEGER               :: iStep, MaxDim
INTEGER               :: iPath, NumPaths
!===================================================================================================================================

IF(BGGas%NumberOfSpecies.LE.0) THEN
  CALL abort(__STAMP__,&
    'Chemistry - Error: Cross-section based chemistry without background gas has not been tested yet!')
END IF

! 1.) Read-in of cross-section data for chemical reactions
DO iCase = 1, CollInf%NumCase
  NumPaths = ChemReac%CollCaseInfo(iCase)%NumOfReactionPaths
  IF(ChemReac%CollCaseInfo(iCase)%HasXSecReaction) ALLOCATE(SpecXSec(iCase)%ReactionPath(1:NumPaths))
  DO iPath = 1, NumPaths
    iReac = ChemReac%CollCaseInfo(iCase)%ReactionIndex(iPath)
    IF(TRIM(ChemReac%ReactModel(iReac)).EQ.'XSec') THEN
      CALL ReadReacXSec(iCase,iPath)
    END IF
  END DO
END DO

! 2.) Add the chemical reaction cross-section to the total collision cross-section
DO iCase = 1, CollInf%NumCase
  ! Collision cross-sections are available
  IF(SpecXSec(iCase)%UseCollXSec) THEN
    ! When no effective cross-section is available, the total cross-section has to be determined
    IF(.NOT.SpecXSec(iCase)%CollXSec_Effective) THEN
      MaxDim = SIZE(SpecXSec(iCase)%CollXSecData,2)
      NumPaths = ChemReac%CollCaseInfo(iCase)%NumOfReactionPaths
      ! Interpolate the reaction cross section at the energy levels of the collision collision cross section
      DO iPath = 1, NumPaths
        DO iStep = 1, MaxDim
          ReactionCrossSection = InterpolateCrossSection_Chem(iCase,iPath,SpecXSec(iCase)%CollXSecData(1,iStep))
          SpecXSec(iCase)%CollXSecData(2,iStep) = SpecXSec(iCase)%CollXSecData(2,iStep) + ReactionCrossSection
        END DO
      END DO
    END IF  ! SpecXSec(iCase)%CollXSec_Effective
  END IF    ! SpecXSec(iCase)%UseCollXSec
END DO

! 3.) Recalculate the null collision probability with the new total cross-section
IF(XSec_NullCollision) THEN
  DO iSpec = 1, nSpecies
    TotalProb = 0.
    DO jSpec = iSpec, nSpecies
      iCase = CollInf%Coll_Case(iSpec,jSpec)
      IF(SpecXSec(iCase)%UseCollXSec) THEN
        CALL DetermineNullCollProb(iCase,iSpec,jSpec)
        TotalProb = TotalProb + SpecXSec(iCase)%ProbNull
        IF(TotalProb.GT.1.0) THEN
          CALL abort(&
          __STAMP__&
          ,'ERROR: Total null collision probability is above unity. Please reduce the time step! Probability is: '&
          ,RealInfoOpt=TotalProb)
        END IF
      END IF
    END DO
  END DO
END IF

END SUBROUTINE MCC_Chemistry_Init


SUBROUTINE FinalizeMCC()
!----------------------------------------------------------------------------------------------------------------------------------!
! finalize dsmc variables
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_MCC_Vars
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
SDEALLOCATE(SpecXSec)
END SUBROUTINE FinalizeMCC

END MODULE MOD_MCC_Init
