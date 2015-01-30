#include "boltzplatz.h"

MODULE MOD_Particle_MPI
!===================================================================================================================================
! Contains global variables provided by the particle surfaces routines
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! required variables
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES

#ifdef MPI
INTERFACE InitParticleMPI
  MODULE PROCEDURE InitParticleMPI
END INTERFACE

INTERFACE FinalizeParticleMPI
  MODULE PROCEDURE FinalizeParticleMPI
END INTERFACE

INTERFACE InitHaloMesh
  MODULE PROCEDURE InitHaloMesh
END INTERFACE


PUBLIC :: InitParticleMPI,FinalizeParticleMPI,InitHaloMesh

!===================================================================================================================================

CONTAINS

SUBROUTINE InitParticleMPI()
!===================================================================================================================================
! read required parameters
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_MPI_Vars
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)')' INIT PARTICLE MPI ... '
IF(ParticleMPIInitIsDone) &
  CALL abort(__STAMP__&
  ,' Particle MPI already initialized!')

PartMPI%COMM   = MPI_COMM_WORLD
PartMPI%myrank = myRank
PartMPI%nProcs = nProcessors
IF(PartMPI%MyRank.EQ.0) THEN
  PartMPI%MPIRoot=.TRUE.
ELSE
  PartMPI%MPIRoot=.FALSE.
END IF

ParticleMPIInitIsDone=.TRUE.
SWRITE(UNIT_stdOut,'(A)')' INIT PARTICLE MPI DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')

END SUBROUTINE InitParticleMPI

SUBROUTINE FinalizeParticleMPI()
!===================================================================================================================================
! read required parameters
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_MPI_Vars
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

ParticleMPIInitIsDone=.FALSE.

END SUBROUTINE FinalizeParticleMPI

SUBROUTINE InitHaloMesh()
!===================================================================================================================================
! communicate all direct neighbor sides from master to slave
! has to be called after GetSideType and MPI_INIT of DG solver
! read required parameters
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_MPI_Vars
USE MOD_PreProc
USE MOD_Particle_Surfaces_vars
USE MOD_Mesh_Vars,                  ONLY:NGeo,nSides
USE MOD_Particle_MPI_Vars,          ONLY:PartMPI
USE MOD_Particle_MPI_Halo,          ONLY:IdentifyHaloMPINeighborhood,ExchangeHaloGeometry
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                 ::BezierSideSize,SendID
INTEGER                 ::iProc,ALLOCSTAT
INTEGER,ALLOCATABLE     ::SideIndex(:)
!===================================================================================================================================

! communicate the MPI Master Sides to Slaves
! all processes have now filled sides and can compute the particles inside the proc region
SendID=1
BezierSideSize=3*(NGeo+1)*(NGeo+1)
DO iNbProc=1,nNbProcs
  ! Start receive face data
  IF(nMPISides_rec(iNbProc,SendID).GT.0)THEN
    nRecVal     =BezierSideSize*nMPISides_rec(iNbProc,SendID)
    SideID_start=OffsetMPISides_rec(iNbProc-1,SendID)+1
    SideID_end  =OffsetMPISides_rec(iNbProc,SendID)
    CALL MPI_IRECV(BezierControlPoints3D(:,:,:,SideID_start:SideID_end),nRecVal,MPI_DOUBLE_PRECISION,  &
                    nbProc(iNbProc),0,MPI_COMM_WORLD,RecRequest_Flux(iNbProc),iError)
  END IF
  ! Start send face data
  IF(nMPISides_send(iNbProc,SendID).GT.0)THEN
    nSendVal    =BezierSideSize*nMPISides_send(iNbProc,SendID)
    SideID_start=OffsetMPISides_send(iNbProc-1,SendID)+1
    SideID_end  =OffsetMPISides_send(iNbProc,SendID)
    CALL MPI_ISEND(BezierControlPoints3D(:,:,:,SideID_start:SideID_end),nSendVal,MPI_DOUBLE_PRECISION,  &
                    nbProc(iNbProc),0,MPI_COMM_WORLD,SendRequest_Flux(iNbProc),iError)
  END IF
END DO !iProc=1,nNBProcs

DO iNbProc=1,nNbProcs
  IF(nMPISides_rec(iNbProc,SendID).GT.0) CALL MPI_WAIT(RecRequest_Flux(iNbProc) ,MPIStatus,iError)
END DO !iProc=1,nNBProcs
! Check send operations
DO iNbProc=1,nNbProcs
  IF(nMPISides_send(iNbProc,SendID).GT.0) CALL MPI_WAIT(SendRequest_Flux(iNbProc),MPIStatus,iError)
END DO !iProc=1,nNBProcs

ALLOCATE(SideIndex(1:nSides),STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) CALL abort(__STAMP__&
,'  Cannot allocate SideIndex!')
SideIndex=0
! check epsilondistance
DO iProc=0,PartMPI%nProcs-1
  IF(iProc.EQ.PartMPI%MyRank) CYCLE
  LOGWRITE(*,*)'  - Identify non-immediate MPI-Neighborhood...'
  !--- AS: identifies which of my node have to be sent to iProc w.r.t. to 
  !        eps vicinity region.
  CALL IdentifyHaloMPINeighborhood(iProc,SideIndex)
  LOGWRITE(*,*)'    ...Done'

  LOGWRITE(*,*)'  - Exchange Geometry of MPI-Neighborhood...'
  CALL ExchangeHaloGeometry(iProc,SideIndex)
  LOGWRITE(*,*)'    ...Done'
  SideIndex(:)=0
END DO 

!  ! Make sure PMPIVAR%MPINeighbor is consistent
!  DO iProc=0,PartMPI%nProcs-1
!    IF (PartMPI%MyRank.EQ.iProc) CYCLE
!    IF (PartMPI%MyRank.LT.iProc) THEN
!      CALL MPI_SEND(PMPIVAR%MPINeighbor(iProc),1,MPI_LOGICAL,iProc,1101,PMPIVAR%COMM,IERROR)
!      CALL MPI_RECV(TmpNeigh,1,MPI_LOGICAL,iProc,1101,PMPIVAR%COMM,MPISTATUS,IERROR)
!    ELSE IF (PMPIVAR%iProc.GT.iProc) THEN
!      CALL MPI_RECV(TmpNeigh,1,MPI_LOGICAL,iProc,1101,PMPIVAR%COMM,MPISTATUS,IERROR)
!      CALL MPI_SEND(PMPIVAR%MPINeighbor(iProc),1,MPI_LOGICAL,iProc,1101,PMPIVAR%COMM,IERROR)
!    END IF
!    IF (TmpNeigh.NEQV.PMPIVAR%MPINeighbor(iProc)) THEN
!      WRITE(*,*) 'WARNING: MPINeighbor set to TRUE',PMPIVAR%iProc,iProc
!      PMPIVAR%MPINeighbor(iProc) = .TRUE.
!    END IF
!  END DO
!  IF(DepositionType.EQ.'shape_function') THEN
!    PMPIVAR%MPINeighbor(PMPIVAR%iProc) = .TRUE.
!  ELSE
!    PMPIVAR%MPINeighbor(PMPIVAR%iProc) = .FALSE.
!  END IF

END SUBROUTINE InitHaloMesh

#endif /*MPI*/
END MODULE MOD_Particle_MPI
