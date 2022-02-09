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

MODULE  MOD_PICInterpolation_tools
!===================================================================================================================================
!
!===================================================================================================================================
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------
INTERFACE GetExternalFieldAtParticle
  MODULE PROCEDURE GetExternalFieldAtParticle
END INTERFACE

INTERFACE GetInterpolatedFieldPartPos
  MODULE PROCEDURE GetInterpolatedFieldPartPos
END INTERFACE

INTERFACE GetEMField
  MODULE PROCEDURE GetEMField
END INTERFACE

INTERFACE InterpolateVariableExternalField
  MODULE PROCEDURE InterpolateVariableExternalField
END INTERFACE

PUBLIC :: GetExternalFieldAtParticle
PUBLIC :: GetInterpolatedFieldPartPos
PUBLIC :: GetEMField
PUBLIC :: InterpolateVariableExternalField
!===================================================================================================================================

CONTAINS


PPURE FUNCTION GetExternalFieldAtParticle(pos)
!===================================================================================================================================
! Get the external field (analytic, variable, etc.) for the particle at position pos
! 4 Methods can be used:
!   0. External field from analytic function (only for convergence tests and compiled with CODE_ANALYZE=ON)
!   1. External E field from user-supplied vector (const.) and
!      B field from CSV file (only Bz) that is interpolated to the particle z-coordinate
!   2. External field from CSV file (only Bz) that is interpolated to the particle z-coordinate
!   3. External E and B field from user-supplied vector (const.)
!===================================================================================================================================
! MODULES
USE MOD_PICInterpolation_Vars ,ONLY: externalField,useVariableExternalField,useAlgebraicExternalField
#ifdef CODE_ANALYZE
USE MOD_PICInterpolation_Vars ,ONLY: DoInterpolationAnalytic
#endif /*CODE_ANALYZE*/
!----------------------------------------------------------------------------------------------------------------------------------
  IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
REAL,INTENT(IN) :: pos(3) ! position x,y,z
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL :: GetExternalFieldAtParticle(1:6)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
GetExternalFieldAtParticle=0.
#ifdef CODE_ANALYZE
! 0. External field from analytic function (only for convergence tests)
IF(DoInterpolationAnalytic)THEN ! use analytic/algebraic functions for the field interpolation
  GetExternalFieldAtParticle(1:6) = GetAnalyticFieldAtParticle(pos)
ELSE ! use variable or fixed external field
#endif /*CODE_ANALYZE*/
!#if (PP_nVar==8))
  IF(useVariableExternalField)THEN
    ! 1. External E field from user-supplied vector (const.) and
    !    B field from CSV file (only Bz) that is interpolated to the particle z-coordinate
    GetExternalFieldAtParticle(1:5) = externalField(1:5)
    GetExternalFieldAtParticle(6) = InterpolateVariableExternalField(pos(3))
  ELSEIF(useAlgebraicExternalField)THEN
    ! 2. External E and B field from algebraic expression that is interpolated to the particle position
    GetExternalFieldAtParticle(1:6) = InterpolateAlgebraicExternalField(pos)
  ELSE
    ! 3. External E and B field from user-supplied vector (const.)
    GetExternalFieldAtParticle(1:6) = externalField(1:6)
  END IF
!#endif /*(PP_nVar==8))*/
#ifdef CODE_ANALYZE
END IF
#endif /*CODE_ANALYZE*/

END FUNCTION GetExternalFieldAtParticle


#ifdef CODE_ANALYZE
PPURE FUNCTION GetAnalyticFieldAtParticle(PartPos)
!===================================================================================================================================
! Calculate the electro-(magnetic) field at the particle's position form an analytic solution
!===================================================================================================================================
! MODULES
USE MOD_PICInterpolation_Vars ,ONLY: AnalyticInterpolationType
!----------------------------------------------------------------------------------------------------------------------------------
  IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
REAL,INTENT(IN)    :: PartPos(1:3)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL :: GetAnalyticFieldAtParticle(1:6)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
GetAnalyticFieldAtParticle(1:6) = 0.
SELECT CASE(AnalyticInterpolationType)
CASE(0) ! 0: const. magnetostatic field: B = B_z = (/ 0 , 0 , 1 T /) = const.
  GetAnalyticFieldAtParticle(6) = 1.0
CASE(1) ! magnetostatic field: B = B_z = B_0 * EXP(x/l)
  ASSOCIATE( B_0 => 1.0, l => 1.0  )
    GetAnalyticFieldAtParticle(6) = B_0 * EXP(PartPos(1) / l)
  END ASSOCIATE
CASE(2)
  ! const. electromagnetic field: B = B_z = (/ 0 , 0 , (x^2+y^2)^0.5 /) = const.
  !                                  E = 1e-2/(x^2+y^2)^(3/2) * (/ x , y , 0. /)
  ! Example from Paper by H. Qin: Why is Boris algorithm so good? (2013)
  ! http://dx.doi.org/10.1063/1.4818428
  ASSOCIATE( x => PartPos(1), y => PartPos(2) )
    ! Ex and Ey
    GetAnalyticFieldAtParticle(1) = 1.0e-2 * (x**2+y**2)**(-1.5) * x
    GetAnalyticFieldAtParticle(2) = 1.0e-2 * (x**2+y**2)**(-1.5) * y
    ! Bz
    GetAnalyticFieldAtParticle(6) = SQRT(x**2+y**2)
  END ASSOCIATE
END SELECT
END FUNCTION GetAnalyticFieldAtParticle
#endif /*CODE_ANALYZE*/


FUNCTION GetInterpolatedFieldPartPos(ElemID,PartID)
!===================================================================================================================================
! Evaluate the electro-(magnetic) field using the reference position and return the field
!===================================================================================================================================
! MODULES
USE MOD_Particle_Tracking_Vars ,ONLY: TrackingMethod
USE MOD_Particle_Vars          ,ONLY: PartPosRef,PDM,PartState,PEM
USE MOD_Eval_xyz               ,ONLY: GetPositionInRefElem
USE MOD_PICDepo_Vars           ,ONLY: DepositionType
#if (PP_TimeDiscMethod>=500) && (PP_TimeDiscMethod<=509)
USE MOD_Particle_Vars          ,ONLY: DoSurfaceFlux
#endif /*(PP_TimeDiscMethod>=500) && (PP_TimeDiscMethod<=509)*/
!----------------------------------------------------------------------------------------------------------------------------------
  IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN) :: ElemID !< Global element ID
INTEGER,INTENT(IN) :: PartID
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL :: GetInterpolatedFieldPartPos(1:6)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                         :: PartPosRef_loc(1:3)
LOGICAL                      :: SucRefPos
#if (PP_TimeDiscMethod>=500) && (PP_TimeDiscMethod<=509)
LOGICAL                      :: NotMappedSurfFluxParts
#else
LOGICAL,PARAMETER            :: NotMappedSurfFluxParts=.FALSE.
#endif /*(PP_TimeDiscMethod>=500) && (PP_TimeDiscMethod<=509)*/
!===================================================================================================================================

! Check Surface Flux Particles
#if (PP_TimeDiscMethod>=500) && (PP_TimeDiscMethod<=509)
NotMappedSurfFluxParts=DoSurfaceFlux !Surfaceflux particles inserted before interpolation and tracking. Field at wall is needed!
#endif /*(PP_TimeDiscMethod>=500) && (PP_TimeDiscMethod<=509)*/

SucRefPos = .TRUE. ! Initialize for all methods

! Check if reference position is required
IF(NotMappedSurfFluxParts .AND.(TrackingMethod.EQ.REFMAPPING))THEN
  IF(PDM%dtFracPush(PartID)) CALL GetPositionInRefElem(PartState(1:3,PartID),PartPosRef_loc(1:3),ElemID)
ELSEIF(TrackingMethod.NE.REFMAPPING)THEN
  CALL GetPositionInRefElem(PartState(1:3,PartID),PartPosRef_loc(1:3),ElemID, isSuccessful = SucRefPos)
ELSE
  PartPosRef_loc(1:3) = PartPosRef(1:3,PartID)
END IF

! Interpolate the field and return the vector
IF ((.NOT.SucRefPos).AND.(TRIM(DepositionType).EQ.'cell_volweight_mean')) THEN
  GetInterpolatedFieldPartPos(1:6) =  GetEMFieldDW(PEM%LocalElemID(PartID),PartState(1:3,PartID))
ELSE
  GetInterpolatedFieldPartPos(1:6) =  GetEMField(PEM%LocalElemID(PartID),PartPosRef_loc(1:3))
END IF
END FUNCTION GetInterpolatedFieldPartPos


PPURE FUNCTION GetEMField(ElemID,PartPosRef_loc)
!===================================================================================================================================
! Evaluate the electro-(magnetic) field using the reference position and return the field
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Eval_xyz      ,ONLY: EvaluateFieldAtRefPos
#if ! (USE_HDG)
USE MOD_DG_Vars       ,ONLY: U
#endif
#ifdef PP_POIS
USE MOD_Equation_Vars ,ONLY: E
#endif
#if USE_HDG
#if PP_nVar==1
USE MOD_Equation_Vars ,ONLY: E
#elif PP_nVar==3
USE MOD_Equation_Vars ,ONLY: B
#else
USE MOD_Equation_Vars ,ONLY: B,E
#endif /*PP_nVar==1*/
#endif /*USE_HDG*/
!----------------------------------------------------------------------------------------------------------------------------------
  IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN) :: ElemID !< Local element ID
REAL,INTENT(IN)    :: PartPosRef_loc(1:3)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL :: GetEMField(1:6)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
#if defined PP_POIS || (USE_HDG && PP_nVar==4)
REAL :: HelperU(1:6,0:PP_N,0:PP_N,0:PP_N)
#endif /*(PP_POIS||USE_HDG)*/
!===================================================================================================================================
GetEMField(1:6)=0.
!--- evaluate at Particle position
#if (PP_nVar==8)
#ifdef PP_POIS
HelperU(1:3,:,:,:) = E(1:3,:,:,:,ElemID)
HelperU(4:6,:,:,:) = U(4:6,:,:,:,ElemID)
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),6,PP_N,HelperU,6,GetEMField(1:6),ElemID)
#else
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),6,PP_N,U(1:6,:,:,:,ElemID),6,GetEMField(1:6),ElemID)
#endif
#else
#ifdef PP_POIS
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),3,PP_N,E(1:3,:,:,:,ElemID),3,GetEMField(1:3),ElemID)
#elif USE_HDG
#if PP_nVar==1
#if (PP_TimeDiscMethod==508)
! Boris: consider B-Field, e.g., from SuperB
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),3,PP_N,E(1:3,:,:,:,ElemID),6,GetEMField(1:6),ElemID)
#else
! Consider only electric fields
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),3,PP_N,E(1:3,:,:,:,ElemID),3,GetEMField(1:3),ElemID)
#endif
#elif PP_nVar==3
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),3,PP_N,B(1:3,:,:,:,ElemID),3,GetEMField(4:6),ElemID)
#else
HelperU(1:3,:,:,:) = E(1:3,:,:,:,ElemID)
HelperU(4:6,:,:,:) = B(1:3,:,:,:,ElemID)
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),6,PP_N,HelperU,6,GetEMField(1:6),ElemID)
#endif
#else
CALL EvaluateFieldAtRefPos(PartPosRef_loc(1:3),3,PP_N,U(1:3,:,:,:,ElemID),3,GetEMField(1:3),ElemID)
#endif
#endif
END FUNCTION GetEMField


FUNCTION GetEMFieldDW(ElemID, PartPos_loc)
!===================================================================================================================================
! Evaluate the electro-(magnetic) field using the reference position and return the field
!===================================================================================================================================
! MODULES
USE MOD_Mesh_Vars     ,ONLY: Elem_xGP
USE MOD_PICInterpolation_Vars ,ONLY: useBGField
USE MOD_Globals
USE MOD_PreProc
#if ! (USE_HDG)
USE MOD_DG_Vars       ,ONLY: U
#endif
#ifdef PP_POIS
USE MOD_Equation_Vars ,ONLY: E
#endif
#if USE_HDG
#if PP_nVar==1
USE MOD_Equation_Vars ,ONLY: E
#elif PP_nVar==3
USE MOD_Equation_Vars ,ONLY: B
#else
USE MOD_Equation_Vars ,ONLY: B,E
#endif /*PP_nVar==1*/
#endif /*USE_HDG*/
!----------------------------------------------------------------------------------------------------------------------------------
  IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN) :: ElemID !< Local element ID
REAL,INTENT(IN)    :: PartPos_loc(1:3)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL :: GetEMFieldDW(1:6)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL    :: HelperU(1:6,0:PP_N,0:PP_N,0:PP_N)
REAL    :: PartDistDepo(0:PP_N,0:PP_N,0:PP_N), DistSum
INTEGER :: k,l,m
REAL    :: norm
!===================================================================================================================================
GetEMFieldDW(1:6)=0.
!--- evaluate at Particle position
#if (PP_nVar==8)
#ifdef PP_POIS
HelperU(1:3,:,:,:) = E(1:3,:,:,:,ElemID)
HelperU(4:6,:,:,:) = U(4:6,:,:,:,ElemID)
#else
HelperU(1:6,:,:,:) = U(1:6,:,:,:,ElemID)
#endif
#else
#ifdef PP_POIS
HelperU(1:3,:,:,:) = E(1:3,:,:,:,ElemID)
#elif USE_HDG
#if PP_nVar==1
#if (PP_TimeDiscMethod==508)
! Boris: consider B-Field, e.g., from SuperB
HelperU(1:3,:,:,:) = E(1:3,:,:,:,ElemID)
#else
! Consider only electric fields
HelperU(1:3,:,:,:) = E(1:3,:,:,:,ElemID)
#endif
#elif PP_nVar==3
HelperU(4:6,:,:,:) = B(1:3,:,:,:,ElemID)
#else
HelperU(1:3,:,:,:) = E(1:3,:,:,:,ElemID)
HelperU(4:6,:,:,:) = B(1:3,:,:,:,ElemID)
#endif
#else
HelperU(1:3,:,:,:) = U(1:3,:,:,:,ElemID)
#endif
#endif

DistSum = 0.0
DO k = 0, PP_N; DO l=0, PP_N; DO m=0, PP_N
  norm = VECNORM(Elem_xGP(1:3,k,l,m, ElemID)-PartPos_loc(1:3))
  IF(norm.GT.0.)THEN
    PartDistDepo(k,l,m) = 1./norm
  ELSE
    PartDistDepo(:,:,:) = 0.
    PartDistDepo(k,l,m) = 1.
    DistSum = 1.
    EXIT
  END IF ! norm.GT.0.
  DistSum = DistSum + PartDistDepo(k,l,m) 
END DO; END DO; END DO

GetEMFieldDW = 0.0
DO k = 0, PP_N; DO l=0, PP_N; DO m=0, PP_N
  GetEMFieldDW(1:6) = GetEMFieldDW(1:6) + PartDistDepo(k,l,m)/DistSum*HelperU(1:6,k,l,m)
END DO; END DO; END DO

IF(useBGField) CALL abort(__STAMP__,' ERROR BG Field not implemented for GetEMFieldDW!')

END FUNCTION GetEMFieldDW


PPURE FUNCTION InterpolateVariableExternalField(Pos)
!===================================================================================================================================
!> Interpolates the variable external field to the z-position
!> NO z-values smaller than VariableExternalField(1,1) are allowed!
!===================================================================================================================================
! MODULES
!USE MOD_Globals
USE MOD_PICInterpolation_Vars   ,ONLY:DeltaExternalField,nIntPoints,VariableExternalField
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)          :: Pos                               !< particle z-position
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL                     :: InterpolateVariableExternalField  !< Bz (magnetic field in z-direction)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                  :: iPos                              !< index in array (equidistant subdivision assumed)
!===================================================================================================================================
iPos = INT((Pos-VariableExternalField(1,1))/DeltaExternalField) + 1
IF(iPos.GE.nIntPoints)THEN ! particle outside of range (greater -> use constant value)
  InterpolateVariableExternalField = VariableExternalField(2,nIntPoints)
ELSEIF(iPos.LT.1)THEN ! particle outside of range (lower -> use constant value)
  InterpolateVariableExternalField = VariableExternalField(2,1)
ELSE ! Linear Interpolation between iPos and iPos+1 B point
  InterpolateVariableExternalField = (VariableExternalField(2,iPos+1) - VariableExternalField(2,iPos)) & !  dy
                                   / (VariableExternalField(1,iPos+1) - VariableExternalField(1,iPos)) & ! /dx
                             * (Pos - VariableExternalField(1,iPos) ) + VariableExternalField(2,iPos)    ! *(z - z_i) + z_i
END IF
END FUNCTION InterpolateVariableExternalField


PPURE FUNCTION InterpolateAlgebraicExternalField(Pos)
!===================================================================================================================================
!> Interpolates the variable external field to the z-position
!> NO z-values smaller than VariableExternalField(1,1) are allowed!
!===================================================================================================================================
! MODULES
!USE MOD_Globals
USE MOD_PICInterpolation_Vars ,ONLY: externalField,AlgebraicExternalField,AlgebraicExternalFieldDelta
#if USE_HDG
USE MOD_Analyze_Vars          ,ONLY: AverageElectricPotential
#endif /*USE_HDG*/
USE MOD_Particle_Mesh_Vars    ,ONLY: GEO
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN) :: Pos(1:3) !< particle position
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL            :: InterpolateAlgebraicExternalField(1:6)  !< E and B field at particle position
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL            :: r !< radius factor
!===================================================================================================================================
ASSOCIATE(&
      x => Pos(1) ,&
      y => Pos(2) ,&
      z => Pos(3)  &
      )
  SELECT CASE (AlgebraicExternalField)
  CASE (1) ! Charoy 2019
#if USE_HDG
    ! Set Ex = Ue/xe
    ASSOCIATE( &
          Ue => AverageElectricPotential ,&
          xe => 2.4e-2                   )
      InterpolateAlgebraicExternalField(1) = Ue/xe
    END ASSOCIATE
#else
    InterpolateAlgebraicExternalField(1) = externalField(1) ! default
#endif /*USE_HDG*/

    ! Set Ey, Ez, Bx and By
    InterpolateAlgebraicExternalField(2:5) = externalField(2:5)

    ! Calc Bz
    ! Original formula
    !ASSOCIATE(&
    !      x     => Pos(1)   ,&
    !      Lx    => 2.50E-2  ,&
    !      xBmax => 0.750E-2 ,&
    !      B0    => 6.00E-3  ,&
    !      BLx   => 1.00E-3  ,&
    !      Bmax  => 10.0E-3  ,&
    !      sigma => 0.625E-2  &
    !      )
    ASSOCIATE( xBmax => 0.750E-2 )
      IF(Pos(1).LT.xBmax)THEN
        ! Original formula
        !ASSOCIATE(a1 => (Bmax-B0)/(1.0-EXP(-0.5*(xBmax/sigma)**2))                              ,&
        !          b1 => (B0 - Bmax*EXP(-0.5*(xBmax/sigma)**2))/(1.0-EXP(-0.5*(xBmax/sigma)**2))  )
        !  InterpolateAlgebraicExternalField(6) = a1 * EXP(-0.5*((x-xBmax)/sigma)**2) + b1
        !END ASSOCIATE
        InterpolateAlgebraicExternalField(6) = 7.7935072222899814E-003 * EXP(-12800.0*(x-xBmax)**2) + 2.2064927777100192E-003
      ELSE
        ! Original formula
        !ASSOCIATE(a2 => (Bmax-BLx)/(1.0-EXP(-0.5*((Lx-xBmax)/sigma)**2))                                  ,&
        !          b2 => (BLx - Bmax*EXP(-0.5*((Lx-xBmax)/sigma)**2))/(1.0-EXP(-0.5*((Lx-xBmax)/sigma)**2))  )
        !  InterpolateAlgebraicExternalField(6) = a2 * EXP(-0.5*((x-xBmax)/sigma)**2) + b2
        !END ASSOCIATE
        InterpolateAlgebraicExternalField(6) = 9.1821845944997683E-003 * EXP(-12800.0*(x-xBmax)**2) + 8.1781540550023306E-004
      END IF ! Pos(1).LT.xBmax
    END ASSOCIATE
    !END ASSOCIATE
  CASE (2) ! Liu 2010: 2D case
    ! Set Ex, Ey, Ez, Bx and Bz
    InterpolateAlgebraicExternalField(1:4) = externalField(1:4)
    InterpolateAlgebraicExternalField(6)   = externalField(6)

    ! Calculate By(x)=Br(x)=Br,0*(x/L)^delta
    ASSOCIATE( L => (GEO%xmaxglob-GEO%xminglob), Br0 => 400.0e-4, d => AlgebraicExternalFieldDelta ) ! Gauss to Tesla is *1e-4
      InterpolateAlgebraicExternalField(5) = Br0*((x/L)**d)
    END ASSOCIATE
  CASE (3) ! Liu 2010: 3D case
    ! Set Ex, Ey, Ez and Bz
    InterpolateAlgebraicExternalField(1:3) = externalField(1:3)
    InterpolateAlgebraicExternalField(6)   = externalField(6)

    ! Calculate By(z)=Br(z)=Br,0*(z/L)^delta
    ASSOCIATE( L => (GEO%zmaxglob-GEO%zminglob), Br0 => 400.0e-4, d => AlgebraicExternalFieldDelta ) ! Gauss to Tesla is *1e-4
      r=Br0*((z/L)**d)/SQRT(x**2+y**2)
      InterpolateAlgebraicExternalField(4) = x*r
      InterpolateAlgebraicExternalField(5) = y*r
    END ASSOCIATE
  END SELECT
END ASSOCIATE
END FUNCTION InterpolateAlgebraicExternalField


END MODULE MOD_PICInterpolation_tools
