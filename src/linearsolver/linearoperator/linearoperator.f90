#include "boltzplatz.h"

MODULE MOD_LinearOperator
!===================================================================================================================================
! Module containing matrix vector operations
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------

INTERFACE MatrixVector
  MODULE PROCEDURE MatrixVector
END INTERFACE

INTERFACE MatrixVectorSource
  MODULE PROCEDURE MatrixVectorSource
END INTERFACE

INTERFACE VectorDotProduct
  MODULE PROCEDURE VectorDotProduct
END INTERFACE

PUBLIC:: MatrixVector, MatrixVectorSource, VectorDotProduct, ElementVectorDotProduct, DENSE_MATMUL
!===================================================================================================================================

CONTAINS

SUBROUTINE MatrixVector(t,Coeff,X,Y)
!===================================================================================================================================
! Computes Matrix Vector Product y=A*x for linear Equations only
! Matrix A = I - Coeff*R
! Attention: Vector x is always U 
! Attention: Result y is always stored in Ut
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars,            ONLY:U,Ut
USE MOD_DG,                 ONLY:DGTimeDerivative_weakForm
USE MOD_LinearSolver_Vars,  ONLY:mass
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)  :: t,Coeff
REAL,INTENT(IN)  :: X(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT) :: Y(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
U=X
CALL DGTimeDerivative_weakForm(t,t,0,doSource=.FALSE.)
! y = (I-Coeff*R)*x = x - Coeff*R*x 
Y = mass*(U - Coeff*Ut)
END SUBROUTINE MatrixVector


SUBROUTINE MatrixVectorSource(t,Coeff,Y)
!===================================================================================================================================
! Computes Matrix Vector Product y=A*x for linear Equations only
! Matrix A = I - Coeff*R
! Attention: Vector x is always U 
! Attention: Result y is always stored in Ut
! Attention: Is only Required for the calculation of the residuum
!            THEREFORE: coeff*DG_Operator(U) is the output pf this routine
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_DG_Vars,           ONLY:U,Ut
USE MOD_DG,                ONLY:DGTimeDerivative_weakForm
USE MOD_Equation,          ONLY:CalcSource
USE MOD_Equation,          ONLY:DivCleaningDamping
USE MOD_LinearSolver_Vars, ONLY:ImplicitSource, LinSolverRHS,mass
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)  :: t,Coeff
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT) :: Y(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

! y =  Coeff*Ut+source
! Residual = b - A x0 
!          = b - x0 + coeff*ut + coeff*Source^n+1

CALL DGTimeDerivative_weakForm(t,t,0,doSource=.FALSE.)
!Y = LinSolverRHS - X0 +coeff*ut
CALL CalcSource(t,1.0,ImplicitSource)
Y = mass*(LinSolverRHS - U +coeff*ut + coeff*ImplicitSource)

END SUBROUTINE MatrixVectorSource


SUBROUTINE VectorDotProduct(a,b,resu)
!===================================================================================================================================
! Computes Dot Product for vectors a and b: resu=a.b
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)   :: a(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
REAL,INTENT(IN)   :: b(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)  :: resu
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iVar,i,j,k,iElem
!===================================================================================================================================

resu=0.
DO iElem=1,PP_nElems
  DO k=0,PP_N
    DO j=0,PP_N
      DO i=0,PP_N
        DO iVar=1,PP_nVar
          resu=resu + a(iVar,i,j,k,iElem)*b(iVar,i,j,k,iElem)
        END DO
      END DO
    END DO
  END DO
END DO

#ifdef MPI
  CALL MPI_ALLREDUCE(MPI_IN_PLACE,resu,1,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,iError)
#endif

END SUBROUTINE VectorDotProduct


SUBROUTINE ElementVectorDotProduct(a,b,resu)
!===================================================================================================================================
! Computes Dot Product for vectors a and b: resu=a.b
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)   :: a(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N)
REAL,INTENT(IN)   :: b(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)  :: resu
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iVar,i,j,k,iElem
!===================================================================================================================================

resu=0.
DO k=0,PP_N
  DO j=0,PP_N
    DO i=0,PP_N
      DO iVar=1,PP_nVar
        resu=resu + a(iVar,i,j,k)*b(iVar,i,j,k)
      END DO
    END DO
  END DO
END DO

END SUBROUTINE ElementVectorDotProduct

SUBROUTINE DENSE_MATMUL(n,A,x,y)
!===================================================================================================================================
! Computes a dense Matrix vector product
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)       :: A(n,n), x(n)
INTEGER,INTENT(IN)    :: n
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)      :: y(n) !
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
INTEGER               :: i,j
!===================================================================================================================================

DO i=1,n
 y(i)=0.
END DO

DO j=1,n
  DO i=1,n
    y(i) = y(i)+A(i,j)*x(j)
  END DO ! i
END DO ! j

END SUBROUTINE DENSE_MATMUL

END MODULE MOD_LinearOperator
