!==================================================================================================================================
! Copyright (c) 2010 - 2019 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
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

MODULE MOD_Radiation
!===================================================================================================================================
! Module for Radiation
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE radiation_main
  MODULE PROCEDURE radiation_main
END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: radiation_main
!===================================================================================================================================

CONTAINS


SUBROUTINE radiation_main(iElem)
!===================================================================================================================================
! Main routine of radiation solver
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Globals_Vars,                  ONLY : Pi
USE MOD_Radiation_Vars,                ONLY : RadiationInput, RadiationSwitches, MacroRadInputParameters, &
                                        Radiation_Emission_spec, Radiation_Absorption_spec, RadiationParameter
USE MOD_Radiation_Excitation,          ONLY : radiation_excitation
USE MOD_Radiation_Atoms,               ONLY : radiation_atoms
USE MOD_Radiation_Molecules,           ONLY : radiation_molecules
USE MOD_Radiation_Continuum,           ONLY : radiation_continuum
USE MOD_Radiation_InstrBroadening,     ONLY : radiation_instrbroadening
USE MOD_PARTICLE_Vars,                 ONLY : nSpecies
USE MOD_Mesh_Vars,                     ONLY: offsetElem
USE MOD_Radiation_ExportSpectrum
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
  INTEGER, INTENT(IN)             :: iElem
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  INTEGER           :: iSpec, w, io_error
!  REAL              :: currentWave, iRan
  REAL              :: em_tot, em_atom, em_mol, em_cont
!===================================================================================================================================

!------- initialize total emission variables
  em_atom = 0.0
  em_mol  = 0.0
  em_cont = 0.0
  em_tot  = 0.0

!IF ( ((iElem+offsetElem).NE.208) .AND. ((iElem+offsetElem).NE.228) .AND. ((iElem+offsetElem).NE.3492) &
!.AND. ((iElem+offsetElem).NE.4743) .AND. ((iElem+offsetElem).NE.6541)) RETURN

  IF (RadiationSwitches%MacroRadInput) THEN
    DO iSpec = 1, nSpecies
      RadiationInput(iSpec)%NumDens   = MacroRadInputParameters(iElem,iSpec,1)
      RadiationInput(iSpec)%Tvib      = MacroRadInputParameters(iElem,iSpec,2)
      RadiationInput(iSpec)%Trot      = MacroRadInputParameters(iElem,iSpec,3)
      RadiationInput(iSpec)%Telec     = MacroRadInputParameters(iElem,iSpec,4)
      RadiationInput(iSpec)%Ttrans(4) = MacroRadInputParameters(iElem,iSpec,5)
    END DO
  END IF

  CALL radiation_excitation()

  IF (RadiationSwitches%bb_at) THEN
    CALL radiation_atoms(iElem, em_atom)
  END IF

  IF (RadiationSwitches%bb_mol) THEN
    CALL radiation_molecules(iElem, em_mol)
  END IF

  CALL radiation_continuum(iElem, em_cont)

  em_atom = em_atom * 4. * Pi
  em_mol  = em_mol  * 4. * Pi
  em_cont = em_cont * 4. * Pi
  em_tot  = em_atom + em_mol + em_cont

  ! WRITE(*,*) 'atomic emission    : ', em_atom, '[w/m³]'
  ! WRITE(*,*) 'molecular emission : ', em_mol, '[w/m³]'
  ! WRITE(*,*) 'continuum emission : ', em_cont, '[w/m³]'
  ! WRITE(*,*) 'total emission     : ', em_tot, '[w/m³]'
  ! WRITE(*,*) ''

  ! READ*

  OPEN(unit=20,file='Radiation_Emission_Absorption.dat',status='replace',action='write', iostat=io_error)
  DO w=1, RadiationParameter%WaveLenDiscr
    WRITE(20,*) RadiationParameter%WaveLen(w)*1.E9, Radiation_Emission_spec(w,1), Radiation_Absorption_spec(w,1)
  END DO
  CLOSE(unit=20)

!------- Write output .dat-file including spectrally resolved emission and absorption for chosen cells
! --- FIRE II Front ---
!  IF( ((iElem+offsetElem).EQ.208) .OR. ((iElem+offsetElem).EQ.228) .OR. ((iElem+offsetElem).EQ.3492) &
!      .OR. ((iElem+offsetElem).EQ.4743) .OR. ((iElem+offsetElem).EQ.6541)) THEN
!    CALL radiation_exportspectrum(iElem, 1)
!    CALL radiation_exportspectrum(iElem, 2)
!  END IF


! --- HEARTED ---
!  IF( ((iElem+offsetElem).EQ.145) .OR. ((iElem+offsetElem).EQ.170) .OR. ((iElem+offsetElem).EQ.3597) &
!      .OR. ((iElem+offsetElem).EQ.5228) ) THEN
!   !  CALL radiation_exportspectrum(iElem, 1)
!    CALL radiation_exportspectrum(iElem, 2)
!  END IF

!------- use slit function
!IF ((iElem+offsetElem).EQ.4743) THEN
!  CALL radiation_instrbroadening(iElem)
!END IF

END SUBROUTINE radiation_main

END MODULE MOD_Radiation
