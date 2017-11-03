#if USE_QDS_DG
#include "boltzplatz.h"

MODULE MOD_QDS_VolInt
!===================================================================================================================================
!> Contains the routines to
!> - determine the volume integral for the QDS-DG method
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
INTERFACE VolIntQDS
  MODULE PROCEDURE VolIntQDS
END INTERFACE

PUBLIC::VolIntQDS
!===================================================================================================================================
CONTAINS

SUBROUTINE VolIntQDS(Ut,dofirstElems)
!===================================================================================================================================
! Computes the volume integral of the weak DG form a la Kopriva
! Attention 1: 1/J(i,j,k) is not yet accounted for
! Attention 2: ut is initialized and is updated with the volume flux derivatives
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars,         ONLY:D_hat
USE MOD_Mesh_Vars,       ONLY:Metrics_fTilde,Metrics_gTilde,Metrics_hTilde
USE MOD_QDS_Flux,        ONLY:EvalFlux3DQDS
USE MOD_QDS_DG_Vars,     ONLY:QDSnVar,nQDSElems
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT)                                  :: Ut(QDSnVar,0:PP_N,0:PP_N,0:PP_N,1:nQDSElems)
LOGICAL,INTENT(IN)                                  :: dofirstElems
! Adds volume contribution to time derivative Ut contained in MOD_DG_Vars (=aufschmutzen!)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,DIMENSION(QDSnVar,0:PP_N,0:PP_N,0:PP_N)      :: f,g,h                ! volume fluxes at all Gauss points
REAL,DIMENSION(QDSnVar)                           :: fTilde,gTilde,hTilde ! auxiliary variables needed to store the fluxes at one GP
INTEGER                                           :: i,j,k,iElem
INTEGER                                           :: l                    ! row index for matrix vector product
INTEGER                                           :: firstElemID, lastElemID
!===================================================================================================================================

IF(dofirstElems)THEN
  firstElemID = 1
  lastElemID  = nQDSElems/2+1
ELSE ! second half of elements
  firstElemID = nQDSElems/2+2
  lastElemID  = nQDSElems
END IF

DO iElem=firstElemID,lastElemID
!DO iElem=1,nQDSElems
  ! Cut out the local DG solution for a grid cell iElem and all Gauss points from the global field
  ! Compute for all Gauss point values the Cartesian flux components
  CALL EvalFlux3DQDS(iElem,f,g,h)

  DO k=0,PP_N
    DO j=0,PP_N
      DO i=0,PP_N
        fTilde=f(:,i,j,k)
        gTilde=g(:,i,j,k)
        hTilde=h(:,i,j,k)
        ! Compute the transformed fluxes with the metric terms
        ! Attention 1: we store the transformed fluxes in f,g,h again
        f(:,i,j,k) = fTilde(:)*Metrics_fTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_fTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_fTilde(3,i,j,k,iElem)
        g(:,i,j,k) = fTilde(:)*Metrics_gTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_gTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_gTilde(3,i,j,k,iElem)
        h(:,i,j,k) = fTilde(:)*Metrics_hTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_hTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_hTilde(3,i,j,k,iElem)
      END DO ! i
    END DO ! j
  END DO ! k


  DO l=0,PP_N
    DO k=0,PP_N
      DO j=0,PP_N
        DO i=0,PP_N
          ! Update the time derivative with the spatial derivatives of the transformed fluxes
          Ut(:,i,j,k,iElem) = Ut(:,i,j,k,iElem) + D_hat(i,l)*f(:,l,j,k) + &
                                                  D_hat(j,l)*g(:,i,l,k) + &
                                                  D_hat(k,l)*h(:,i,j,l)
        END DO !i
      END DO ! j
    END DO ! k
  END DO ! l
END DO ! iElem
END SUBROUTINE VolIntQDS


SUBROUTINE VolIntQDS2(Ut,dofirstElems)
!===================================================================================================================================
! Computes the volume integral of the weak DG form a la Kopriva
! Attention 1: 1/J(i,j,k) is not yet accounted for
! Attention 2: ut is initialized and is updated with the volume flux derivatives
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars,         ONLY:D_hat_T,D_T,D,D_hat
USE MOD_Mesh_Vars,       ONLY:Metrics_fTilde,Metrics_gTilde,Metrics_hTilde
USE MOD_QDS_Flux,        ONLY:EvalFlux3DQDS
USE MOD_QDS_DG_Vars,     ONLY:QDSnVar,nQDSElems
USE MOD_QDS_DG_Vars,     ONLY:UQDS
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT)                                  :: Ut(QDSnVar,0:PP_N,0:PP_N,0:PP_N,1:nQDSElems)
LOGICAL,INTENT(IN)                                  :: dofirstElems
! Adds volume contribution to time derivative Ut contained in MOD_DG_Vars (=aufschmutzen!)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,DIMENSION(QDSnVar,0:PP_N,0:PP_N,0:PP_N)      :: f,g,h                ! volume fluxes at all Gauss points
REAL,DIMENSION(QDSnVar)                           :: fTilde,gTilde,hTilde ! auxiliary variables needed to store the fluxes at one GP
INTEGER                                           :: i,j,k,iElem
INTEGER                                           :: l                    ! row index for matrix vector product
INTEGER                                           :: firstElemID, lastElemID
INTEGER                                           :: iPart
!===================================================================================================================================

IF(dofirstElems)THEN
  firstElemID = 1
  lastElemID  = nQDSElems/2+1
ELSE ! second half of elements
  firstElemID = nQDSElems/2+2
  lastElemID  = nQDSElems
END IF

DO iElem=firstElemID,lastElemID
!DO iElem=1,nQDSElems
  ! Cut out the local DG solution for a grid cell iElem and all Gauss points from the global field
  ! Compute for all Gauss point values the Cartesian flux components
  !CALL EvalFlux3DQDS(iElem,f,g,h)

  DO k=0,PP_N
    DO j=0,PP_N
      DO i=0,PP_N
        DO iPart=0,7
        !f(1+5*iVar,i,j,k) = UQDS(2+5*iVar,i,j,k,iElem)*UQDS(1+5*iVar,i,j,k,iElem) 
          fTilde(1+5*iPart:5+5*iPart)= UQDS(2+5*iPart,i,j,k,iElem)
          gTilde(1+5*iPart:5+5*iPart)= UQDS(3+5*iPart,i,j,k,iElem)
          hTilde(1+5*iPart:5+5*iPart)= UQDS(4+5*iPart,i,j,k,iElem)
        END DO
        ! Compute the transformed fluxes with the metric terms
        ! Attention 1: we store the transformed fluxes in f,g,h again
        f(:,i,j,k) = fTilde(:)*Metrics_fTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_fTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_fTilde(3,i,j,k,iElem)
        g(:,i,j,k) = fTilde(:)*Metrics_gTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_gTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_gTilde(3,i,j,k,iElem)
        h(:,i,j,k) = fTilde(:)*Metrics_hTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_hTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_hTilde(3,i,j,k,iElem)
      END DO ! i
    END DO ! j
  END DO ! k


  DO k=0,PP_N
    DO j=0,PP_N
      DO i=0,PP_N
        Ut(:,i,j,k,iElem) = D_Hat(0,i)*f(:,0,j,k)*UQDS(:,0,j,k,iElem) + &
                            D_Hat(0,j)*g(:,i,0,k)*UQDS(:,i,0,k,iElem) + &
                            D_Hat(0,k)*h(:,i,j,0)*UQDS(:,i,j,0,iElem) - &
                          0*  D_T(0,i)*f(:,0,j,k)*UQDS(:,i,j,k,iElem)    - &
                          0*  D_T(0,j)*g(:,i,0,k)*UQDS(:,i,j,k,iElem)    - &
                          0*  D_T(0,k)*h(:,i,j,0)*UQDS(:,i,j,k,iElem)
        DO l=1,PP_N
          Ut(:,i,j,k,iElem) = Ut(:,i,j,k,iElem) + D_Hat(l,i)*f(:,l,j,k)*UQDS(:,l,j,k,iElem)    + &
                                                  D_Hat(l,j)*g(:,i,l,k)*UQDS(:,i,l,k,iElem)    + &
                                                  D_Hat(l,k)*h(:,i,j,l)*UQDS(:,i,j,l,iElem)    - &
                                               0*   D_T(l,i)*f(:,l,j,k)*UQDS(:,i,j,k,iElem)        - &
                                               0*   D_T(l,j)*g(:,i,l,k)*UQDS(:,i,j,k,iElem)        - &
                                               0*   D_T(l,k)*h(:,i,j,l)*UQDS(:,i,j,k,iElem)
        END DO !l
      END DO ! i
    END DO ! j
  END DO ! k


END DO ! iElem
END SUBROUTINE VolIntQDS2

SUBROUTINE VolIntQDS3(Ut,dofirstElems)
!===================================================================================================================================
! Computes the volume integral of the weak DG form a la Kopriva
! Attention 1: 1/J(i,j,k) is not yet accounted for
! Attention 2: ut is initialized and is updated with the volume flux derivatives
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars,         ONLY:D_hat_T,D_T,D,D_hat
USE MOD_Mesh_Vars,       ONLY:Metrics_fTilde,Metrics_gTilde,Metrics_hTilde
USE MOD_QDS_DG_Vars,     ONLY:QDSnVar,nQDSElems
USE MOD_QDS_DG_Vars,     ONLY:UQDS
USE MOD_QDS_Flux,        ONLY:EvalFlux3DQDS
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT)                                  :: Ut(QDSnVar,0:PP_N,0:PP_N,0:PP_N,1:nQDSElems)
LOGICAL,INTENT(IN)                                  :: dofirstElems
! Adds volume contribution to time derivative Ut contained in MOD_DG_Vars (=aufschmutzen!)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,DIMENSION(QDSnVar,0:PP_N,0:PP_N,0:PP_N)      :: f,g,h                ! volume fluxes at all Gauss points
REAL,DIMENSION(QDSnVar)                           :: fTilde,gTilde,hTilde ! auxiliary variables needed to store the fluxes at one GP
INTEGER                                           :: i,j,k,iElem
INTEGER                                           :: l                    ! row index for matrix vector product
INTEGER                                           :: firstElemID, lastElemID
INTEGER                                           :: iPart
!===================================================================================================================================

IF(dofirstElems)THEN
  firstElemID = 1
  lastElemID  = nQDSElems/2+1
ELSE ! second half of elements
  firstElemID = nQDSElems/2+2
  lastElemID  = nQDSElems
END IF

DO iElem=firstElemID,lastElemID
!DO iElem=1,nQDSElems
  ! Cut out the local DG solution for a grid cell iElem and all Gauss points from the global field
  ! Compute for all Gauss point values the Cartesian flux components
  CALL EvalFlux3DQDS(iElem,f,g,h)

  DO k=0,PP_N
    DO j=0,PP_N
      DO i=0,PP_N
        fTilde=f(:,i,j,k)
        gTilde=g(:,i,j,k)
        hTilde=h(:,i,j,k)
        ! Compute the transformed fluxes with the metric terms
        ! Attention 1: we store the transformed fluxes in f,g,h again
        f(:,i,j,k) = fTilde(:)*Metrics_fTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_fTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_fTilde(3,i,j,k,iElem)
        g(:,i,j,k) = fTilde(:)*Metrics_gTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_gTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_gTilde(3,i,j,k,iElem)
        h(:,i,j,k) = fTilde(:)*Metrics_hTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_hTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_hTilde(3,i,j,k,iElem)
      END DO ! i
    END DO ! j
  END DO ! k


  DO l=0,PP_N
    DO k=0,PP_N
      DO j=0,PP_N
        DO i=0,PP_N
          ! Update the time derivative with the spatial derivatives of the transformed fluxes
          Ut(:,i,j,k,iElem) = Ut(:,i,j,k,iElem) + D_hat(i,l)*f(:,l,j,k) + &
                                                  D_hat(j,l)*g(:,i,l,k) + &
                                                  D_hat(k,l)*h(:,i,j,l) - &
                                                  D(i,l)*f(:,l,j,k) - &
                                                  D(j,l)*g(:,i,l,k) - &
                                                  D(k,l)*h(:,i,j,l)
        END DO !i
      END DO ! j
    END DO ! k
  END DO ! l

 ! DO k=0,PP_N
 !   DO j=0,PP_N
 !     DO i=0,PP_N
 !       Ut(:,i,j,k,iElem) = D_Hat(0,i)*f(:,0,j,k) + &
 !                          D_Hat(0,j)*g(:,i,0,k) + &
 !                          D_Hat(0,k)*h(:,i,j,0) - &
 !                         0*  D_T(0,i)*f(:,0,j,k)*UQDS(:,i,j,k,iElem)    - &
 !                         0*  D_T(0,j)*g(:,i,0,k)*UQDS(:,i,j,k,iElem)    - &
 !                        0*  D_T(0,k)*h(:,i,j,0)*UQDS(:,i,j,k,iElem)
 !       DO l=1,PP_N
 !         Ut(:,i,j,k,iElem) = Ut(:,i,j,k,iElem) + D_Hat(l,i)*f(:,l,j,k)   + &
 !                                                 D_Hat(l,j)*g(:,i,l,k)   + &
 !                                                D_Hat(l,k)*h(:,i,j,l)- &
 !                                              0*   D_T(l,i)*f(:,l,j,k)*UQDS(:,i,j,k,iElem)        - &
 !                                              0*   D_T(l,j)*g(:,i,l,k)*UQDS(:,i,j,k,iElem)        - &
 !                                              0*   D_T(l,k)*h(:,i,j,l)*UQDS(:,i,j,k,iElem)
 !       END DO !l
 !     END DO ! i
 !   END DO ! j
  !END DO ! k


END DO ! iElem
END SUBROUTINE VolIntQDS3


END MODULE MOD_QDS_VolInt
#endif /*USE_QDS_DG*/
