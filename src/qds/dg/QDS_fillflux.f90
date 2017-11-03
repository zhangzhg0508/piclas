#if USE_QDS_DG
#include "boltzplatz.h"

MODULE MOD_QDS_FillFlux
!===================================================================================================================================
!> Contains the routines to
!> - determine the surface flux for the QDS-DG variables for
!>   * inner sides (Riemann solution)
!>   * boundary condition sides
!===================================================================================================================================
! MODULES
!USE MOD_io_HDF5
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
INTERFACE FillFluxQDS
  MODULE PROCEDURE FillFluxQDS
END INTERFACE

PUBLIC::FillFluxQDS
!===================================================================================================================================
CONTAINS
SUBROUTINE FillFluxQDS(t,tDeriv,FluxQDS_Master,FluxQDS_Slave,UQDS_Master,UQDS_Slave,doMPISides)
!===================================================================================================================================
!
!===================================================================================================================================
! MODULES
USE MOD_GLobals
USE MOD_PreProc
USE MOD_Mesh_Vars,           ONLY:NormVec,SurfElem
USE MOD_Mesh_Vars,           ONLY:nSides,nBCSides
USE MOD_Mesh_Vars,           ONLY:NormVec,TangVec1, tangVec2, SurfElem,Face_xGP
USE MOD_Mesh_Vars,           ONLY:firstMPISide_MINE,lastMPISide_MINE,firstInnerSide,firstBCSide,lastInnerSide
USE MOD_QDS_Riemann,         ONLY:RiemannQDS
USE MOD_QDS_GetBoundaryFlux, ONLY:GetBoundaryFluxQDS
USE MOD_QDS_DG_Vars,         ONLY:QDSnVar
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
LOGICAL,INTENT(IN) :: doMPISides  != .TRUE. only MINE MPISides are filled, =.FALSE. InnerSides  
REAL,INTENT(IN)    :: t           ! time
INTEGER,INTENT(IN) :: tDeriv      ! deriv
REAL,INTENT(IN)    :: UQDS_Master(QDSnVar,0:PP_N,0:PP_N,1:nSides)
REAL,INTENT(IN)    :: UQDS_slave (QDSnVar,0:PP_N,0:PP_N,1:nSides)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)   :: FluxQDS_Master(1:QDSnVar,0:PP_N,0:PP_N,nSides)
REAL,INTENT(OUT)   :: FluxQDS_Slave(1:QDSnVar,0:PP_N,0:PP_N,nSides)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: SideID,p,q,firstSideID_wo_BC,firstSideID ,lastSideID
!===================================================================================================================================

! fill flux for sides ranging between firstSideID and lastSideID using RiemannQDS solver
IF(doMPISides)THEN 
  ! fill only flux for MINE MPISides
  ! fill only flux for MINE MPISides (where the local proc is master) 
  firstSideID_wo_BC = firstMPISide_MINE
  firstSideID = firstMPISide_MINE
  lastSideID =  lastMPISide_MINE
ELSE
  ! fill only InnerSides
  ! fill only InnerSides that do not need communication
  firstSideID_wo_BC = firstInnerSide ! for fluxes
  firstSideID = firstBCSide    ! include BCs for master sides
  lastSideID = lastInnerSide
END IF

! Compute fluxes on PP_N, no additional interpolation required
DO SideID=firstSideID,lastSideID
  CALL RiemannQDS(FluxQDS_Master(1:QDSnVar,:,:,SideID),UQDS_Master( :,:,:,SideID),UQDS_Slave(  :,:,:,SideID),NormVec(:,:,:,SideID))
END DO ! SideID
  
IF(.NOT.doMPISides)THEN
  CALL GetBoundaryFluxQDS(t,tDeriv,FluxQDS_Master (1:QDSnVar,0:PP_N,0:PP_N,1:nBCSides) &
                                  ,UQDS_Master    (1:QDSnVar,0:PP_N,0:PP_N,1:nBCSides) &
                                  ,NormVec        (1:3      ,0:PP_N,0:PP_N,1:nBCSides) &
                                  ,TangVec1       (1:3      ,0:PP_N,0:PP_N,1:nBCSides) &
                                  ,TangVec2       (1:3      ,0:PP_N,0:PP_N,1:nBCSides) &
                                  ,Face_XGP       (1:3      ,0:PP_N,0:PP_N,1:nBCSides) )
END IF

! Apply surface element size
DO SideID=firstSideID,lastSideID
  DO q=0,PP_N; DO p=0,PP_N
    FluxQDS_Master(:,p,q,SideID)=FluxQDS_Master(:,p,q,SideID)*SurfElem(p,q,SideID)
  END DO; END DO
END DO

! copy flux from Master side to slave side, DO not change sign
FluxQDS_slave(:,:,:,firstSideID:lastSideID) = FluxQDS_master(:,:,:,firstSideID:lastSideID)


END SUBROUTINE FillFluxQDS


END MODULE MOD_QDS_FillFlux
#endif /*USE_QDS_DG*/
