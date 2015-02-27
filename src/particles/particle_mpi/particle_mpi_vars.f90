#include "boltzplatz.h"

MODULE MOD_Particle_MPI_Vars
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
INTEGER,ALLOCATABLE :: PartHaloToProc(:,:)                                   ! containing native elemid and native proc id
                                                                             ! 1 - Native_Elem_ID
                                                                             ! 2 - Rank of Proc
                                                                             ! 3 - local neighbor id
INTEGER             :: myRealKind
LOGICAL                                  :: ParticleMPIInitIsDone=.FALSE.
INTEGER, ALLOCATABLE                     :: casematrix(:,:)                   ! matrix to compute periodic cases
INTEGER                                  :: NbrOfCases                        ! Number of periodic cases
#ifdef MPI
INTEGER                                  :: PartCommSize                      ! Number of REAL entries for particle communication
                                                                              ! should think about own MPI-Data-Type
REAL                                     :: SafetyFactor                      ! Factor to scale the halo region with MPI
REAL                                     :: halo_eps_velo                     ! halo_eps_velo
REAL                                     :: halo_eps                          ! length of halo-region
REAL                                     :: halo_eps2                         ! length of halo-region^2

TYPE tPartMPIConnect
!  TYPE(tSidePtr)               , POINTER :: tagToSide(:)           =>NULL()   ! gives side pointer for each MPI tag
  !TYPE(tPeriodicPtr)       , ALLOCATABLE :: Periodic(:)                       ! data for different periodic borders for process
  LOGICAL                                :: isBGMNeighbor                     ! Flag: which process is neighber wrt. bckgrnd mesh
  LOGICAL                                :: isBGMPeriodicNeighbor             ! Flag: which process is neighber wrt. bckgrnd mesh
!  LOGICAL                      , POINTER :: myBGMPoint(:,:,:)      =>NULL()   ! Flag: does BGM point(i,j,k) belong to me?
!  LOGICAL                      , POINTER :: yourBGMPoint(:,:,:)    =>NULL()   ! Flag: does BGM point(i,j,k) belong to process?
  INTEGER                  , ALLOCATABLE :: BGMBorder(:,:)            ! indices of border nodes (1=min 2=max,xyz)
!  INTEGER                                :: nmyBGMPoints                      ! Number of BGM points in my part of the border
!  INTEGER                                :: nyourBGMPoints                    ! Number of BGM points in your part of border
  INTEGER                                :: BGMPeriodicBorderCount            ! Number(#) of overlapping areas due to periodic bc
END TYPE

TYPE tPartMPIVAR
  TYPE(tPartMPIConnect)        , ALLOCATABLE :: MPIConnect(:)             ! MPI connect for each process
  INTEGER                                :: COMM                          ! MPI communicator for PIC GTS region
  INTEGER                                :: nProcs                        ! number of MPI processes for particles
  INTEGER                                :: MyRank                        ! MyRank of PartMPIVAR%COMM
  LOGICAL                                :: MPIRoot                       ! Root, MPIRank=0
  INTEGER                                :: nMPINeighbors                 ! number of MPI-Neighbors with HALO
  LOGICAL,ALLOCATABLE                    :: isMPINeighbor(:)              ! list of possible neighbors
  INTEGER,ALLOCATABLE                    :: MPINeighbor(:)                ! list containing the rank of MPI-neighbors
END TYPE

TYPE (tPartMPIVAR)                       :: PartMPI

TYPE tMPIMessage
  REAL,ALLOCATABLE                      :: content(:,:)                   ! message buffer real
END TYPE

TYPE(tMPIMessage),ALLOCATABLE  :: PartRecvBuf(:)

TYPE tParticleMPIExchange
  INTEGER,ALLOCATABLE            :: nPartsSend(:)    ! only mpi neighbors
  INTEGER,ALLOCATABLE            :: nPartsRecv(:)    ! only mpi neighbors
  INTEGER                        :: nMPIParticles    ! number of all received particles
  INTEGER,ALLOCATABLE            :: SendRequest(:,:) ! send requirest message handle 1 - Number, 2-Message
  INTEGER,ALLOCATABLE            :: RecvRequest(:,:) ! recv request message handle,  1 - Number, 2-Message

!  INTEGER                       ,POINTER :: MPINbrOfParticles(:)
!  INTEGER                       ,POINTER :: MPIProcNbr(:)
!  INTEGER                       ,POINTER :: MPITags(:)
!  TYPE(tMPIMessage)             ,POINTER :: send_message(:)
!  INTEGER                       ,POINTER :: nbrOfSendParticles(:,:)  ! (1:nProcs,1:2) 1: pure MPI part, 2: shape part
!  INTEGER                       ,POINTER :: NbrArray(:)  ! (1:nProcs*2)
!  INTEGER                       ,POINTER :: nbrOfSendParticlesEmission(:)  ! (1:nProcs)
END TYPE
 
!TYPE (tPartMPIExchange)                  :: PMPIInsert
TYPE (tParticleMPIExchange)                :: PartMPIExchange


#endif /*MPI*/
!===================================================================================================================================

END MODULE MOD_Particle_MPI_Vars
