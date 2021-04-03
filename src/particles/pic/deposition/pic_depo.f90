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

MODULE MOD_PICDepo
!===================================================================================================================================
! MOD PIC Depo
!===================================================================================================================================
 IMPLICIT NONE
 PRIVATE
!===================================================================================================================================
INTERFACE Deposition
  MODULE PROCEDURE Deposition
END INTERFACE

INTERFACE InitializeDeposition
  MODULE PROCEDURE InitializeDeposition
END INTERFACE

INTERFACE FinalizeDeposition
  MODULE PROCEDURE FinalizeDeposition
END INTERFACE

PUBLIC:: Deposition, InitializeDeposition, FinalizeDeposition, DefineParametersPICDeposition
!===================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Define parameters for PIC Deposition
!==================================================================================================================================
SUBROUTINE DefineParametersPICDeposition()
! MODULES
USE MOD_Globals
USE MOD_ReadInTools      ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%CreateStringOption( 'PIC-TimeAverageFile'      , 'Read charge density from .h5 file and save to PartSource\n'//&
                                                           'WARNING: Currently not correctly implemented for shared memory', 'none')
CALL prms%CreateLogicalOption('PIC-RelaxDeposition'      , 'Relaxation of current PartSource with RelaxFac\n'//&
                                                           'into PartSourceOld', '.FALSE.')
CALL prms%CreateRealOption(   'PIC-RelaxFac'             , 'Relaxation factor of current PartSource with RelaxFac\n'//&
                                                           'into PartSourceOld', '0.001')

CALL prms%CreateLogicalOption('PIC-shapefunction-charge-conservation', 'Enable charge conservation.', '.FALSE.')
CALL prms%CreateRealOption(   'PIC-shapefunction-radius'             , 'Radius of shape function'   , '1.')
CALL prms%CreateIntOption(    'PIC-shapefunction-alpha'              , 'Exponent of shape function' , '2')
CALL prms%CreateIntOption(    'PIC-shapefunction-dimension'          , '1D                          , 2D or 3D shape function', '3')
CALL prms%CreateIntOption(    'PIC-shapefunction-direction'          , &
    'Only required for PIC-shapefunction-dimension 1 or 2: Shape function direction for 1D (the direction in which the charge '//&
    'will be distributed) and 2D (the direction in which the charge will be constant)', '1')
CALL prms%CreateLogicalOption(  'PIC-shapefunction-3D-deposition' ,'Deposit the charge over volume (3D)\n'//&
                                                                   ' or over a line (1D)/area(2D)\n'//&
                                                                   '1D shape function: volume or line\n'//&
                                                                   '2D shape function: volume or area', '.TRUE.')
CALL prms%CreateRealOption(     'PIC-shapefunction-radius0', 'Minimum shape function radius (for cylindrical and spherical)', '1.')
CALL prms%CreateRealOption(     'PIC-shapefunction-scale'  , 'Scaling factor of shape function radius '//&
                                                             '(for cylindrical and spherical)', '0.')
CALL prms%CreateRealOption(     'PIC-shapefunction-adaptive-DOF'  ,'Average number of DOF in shape function radius (assuming a '//&
    'Cartesian grid with equal elements). Only implemented for PIC-Deposition-Type = shape_function_adaptive (2). The maximum '//&
    'number of DOF is limited by the polynomial degree and is (4/3)*Pi*(N+1)^3', '33.')

END SUBROUTINE DefineParametersPICDeposition


SUBROUTINE InitializeDeposition
!===================================================================================================================================
! Initialize the deposition variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Basis                  ,ONLY: BarycentricWeights,InitializeVandermonde
USE MOD_Basis                  ,ONLY: LegendreGaussNodesAndWeights,LegGaussLobNodesAndWeights
USE MOD_ChangeBasis            ,ONLY: ChangeBasis3D
USE MOD_Dielectric_Vars        ,ONLY: DoDielectricSurfaceCharge
USE MOD_Interpolation          ,ONLY: GetVandermonde
USE MOD_Interpolation_Vars     ,ONLY: xGP,wBary,NodeType,NodeTypeVISU
USE MOD_Mesh_Vars              ,ONLY: nElems,sJ,Vdm_EQ_N
USE MOD_Particle_Vars
USE MOD_Particle_Mesh_Vars     ,ONLY: nUniqueGlobalNodes
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemNodeID_Shared,NodeInfo_Shared,NodeToElemInfo,NodeToElemMapping
USE MOD_PICDepo_Method         ,ONLY: InitDepositionMethod
USE MOD_PICDepo_Vars
USE MOD_PICDepo_Tools          ,ONLY: CalcCellLocNodeVolumes,ReadTimeAverage
USE MOD_PICInterpolation_Vars  ,ONLY: InterpolationType
USE MOD_Preproc
USE MOD_ReadInTools            ,ONLY: GETREAL,GETINT,GETLOGICAL,GETSTR,GETREALARRAY,GETINTARRAY
#if USE_MPI
USE MOD_Mesh_Tools             ,ONLY: GetGlobalElemID
USE MOD_MPI_Shared_Vars        ,ONLY: nComputeNodeTotalElems,nComputeNodeProcessors,myComputeNodeRank,MPI_COMM_LEADERS_SHARED
USE MOD_MPI_Shared_Vars        ,ONLY: MPI_COMM_SHARED,myLeaderGroupRank,nLeaderGroupProcs
USE MOD_MPI_Shared
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemInfo_Shared
USE MOD_Restart_Vars           ,ONLY: DoRestart
#endif /*USE_MPI*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,ALLOCATABLE          :: xGP_tmp(:),wGP_tmp(:)
INTEGER                   :: ALLOCSTAT, iElem, i, j, k, kk, ll, mm
INTEGER                   :: jElem, NonUniqueNodeID,iNode
REAL                      :: DetLocal(1,0:PP_N,0:PP_N,0:PP_N), DetJac(1,0:1,0:1,0:1)
REAL, ALLOCATABLE         :: Vdm_tmp(:,:)
CHARACTER(255)            :: TimeAverageFile
INTEGER                   :: UniqueNodeID
#if USE_MPI
INTEGER(KIND=MPI_ADDRESS_KIND)   :: MPISharedSize
INTEGER                   :: SendNodeCount, GlobalElemNode, GlobalElemRank, iProc
INTEGER                   :: TestElemID
LOGICAL,ALLOCATABLE       :: NodeDepoMapping(:,:)
INTEGER                   :: RecvRequest(0:nLeaderGroupProcs-1),SendRequest(0:nLeaderGroupProcs-1),firstNode,lastNode
#endif
!===================================================================================================================================

SWRITE(UNIT_stdOut,'(A)') ' INIT PARTICLE DEPOSITION...'

IF(.NOT.DoDeposition) THEN
  ! fill deposition type with empty string
  DepositionType='NONE'
  OutputSource=.FALSE.
  RelaxDeposition=.FALSE.
  RETURN
END IF

! Initialize Deposition
!CALL InitDepositionMethod()

!--- Allocate arrays for charge density collection and initialize
#if USE_MPI
MPISharedSize = INT(4*(PP_N+1)*(PP_N+1)*(PP_N+1)*nComputeNodeTotalElems,MPI_ADDRESS_KIND)*MPI_ADDRESS_KIND
CALL Allocate_Shared(MPISharedSize,(/4*(PP_N+1)*(PP_N+1)*(PP_N+1)*nComputeNodeTotalElems/),PartSource_Shared_Win,PartSource_Shared)
CALL MPI_WIN_LOCK_ALL(0,PartSource_Shared_Win,IERROR)
PartSource(1:4,0:PP_N,0:PP_N,0:PP_N,1:nComputeNodeTotalElems) => PartSource_Shared(1:4*(PP_N+1)*(PP_N+1)*(PP_N+1)*nComputeNodeTotalElems)
ALLOCATE(PartSourceProc(   1:4,0:PP_N,0:PP_N,0:PP_N,1:nSendShapeElems))
#else
ALLOCATE(PartSource(1:4,0:PP_N,0:PP_N,0:PP_N,nElems))
#endif
#if USE_MPI
IF(myComputeNodeRank.EQ.0) THEN
#endif
  PartSource=0.
#if USE_MPI
END IF
CALL MPI_WIN_SYNC(PartSource_Shared_Win,IERROR)
CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)
#endif
PartSourceConstExists=.FALSE.

!--- check if relaxation of current PartSource with RelaxFac into PartSourceOld
RelaxDeposition = GETLOGICAL('PIC-RelaxDeposition','F')
IF (RelaxDeposition) THEN
  RelaxFac     = GETREAL('PIC-RelaxFac','0.001')
#if ((USE_HDG) && (PP_nVar==1))
  ALLOCATE(PartSourceOld(1,1:2,0:PP_N,0:PP_N,0:PP_N,nElems),STAT=ALLOCSTAT)
#else
  ALLOCATE(PartSourceOld(1:4,1:2,0:PP_N,0:PP_N,0:PP_N,nElems),STAT=ALLOCSTAT)
#endif
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
__STAMP__&
,'ERROR in pic_depo.f90: Cannot allocate PartSourceOld!')
  END IF
  PartSourceOld=0.
  OutputSource = .TRUE.
ELSE
  OutputSource = GETLOGICAL('PIC-OutputSource','F')
END IF

!--- check if charge density is computed from TimeAverageFile
TimeAverageFile = GETSTR('PIC-TimeAverageFile','none')
IF (TRIM(TimeAverageFile).NE.'none') THEN
  CALL abort(&
  __STAMP__&
  ,'This feature is currently not working! PartSource must be correctly handled in shared memory context.')
  CALL ReadTimeAverage(TimeAverageFile)
  IF (.NOT.RelaxDeposition) THEN
  !-- switch off deposition: use only the read PartSource
    DoDeposition=.FALSE.
    DepositionType='constant'
    RETURN
  ELSE
  !-- use read PartSource as initialValue for relaxation
  !-- CAUTION: will be overwritten by DG_Source if present in restart-file!
    DO iElem = 1, nElems
      DO kk = 0, PP_N
        DO ll = 0, PP_N
          DO mm = 0, PP_N
#if ((USE_HDG) && (PP_nVar==1))
            PartSourceOld(1,1,mm,ll,kk,iElem) = PartSource(4,mm,ll,kk,iElem)
            PartSourceOld(1,2,mm,ll,kk,iElem) = PartSource(4,mm,ll,kk,iElem)
#else
            PartSourceOld(1:4,1,mm,ll,kk,iElem) = PartSource(1:4,mm,ll,kk,iElem)
            PartSourceOld(1:4,2,mm,ll,kk,iElem) = PartSource(1:4,mm,ll,kk,iElem)
#endif
          END DO !mm
        END DO !ll
      END DO !kk
    END DO !iElem
  END IF
END IF

!--- init DepositionType-specific vars
SELECT CASE(TRIM(DepositionType))
CASE('cell_volweight')
  ALLOCATE(CellVolWeightFac(0:PP_N),wGP_tmp(0:PP_N) , xGP_tmp(0:PP_N))
  ALLOCATE(CellVolWeight_Volumes(0:1,0:1,0:1,nElems))
  CellVolWeightFac(0:PP_N) = xGP(0:PP_N)
  CellVolWeightFac(0:PP_N) = (CellVolWeightFac(0:PP_N)+1.0)/2.0
  CALL LegendreGaussNodesAndWeights(1,xGP_tmp,wGP_tmp)
  ALLOCATE( Vdm_tmp(0:1,0:PP_N))
  CALL InitializeVandermonde(PP_N,1,wBary,xGP,xGP_tmp,Vdm_tmp)
  DO iElem=1, nElems
    DO k=0,PP_N
      DO j=0,PP_N
        DO i=0,PP_N
          DetLocal(1,i,j,k)=1./sJ(i,j,k,iElem)
        END DO ! i=0,PP_N
      END DO ! j=0,PP_N
    END DO ! k=0,PP_N
    CALL ChangeBasis3D(1,PP_N, 1,Vdm_tmp, DetLocal(:,:,:,:),DetJac(:,:,:,:))
    DO k=0,1
      DO j=0,1
        DO i=0,1
          CellVolWeight_Volumes(i,j,k,iElem) = DetJac(1,i,j,k)*wGP_tmp(i)*wGP_tmp(j)*wGP_tmp(k)
        END DO ! i=0,PP_N
      END DO ! j=0,PP_N
    END DO ! k=0,PP_N
  END DO
  DEALLOCATE(Vdm_tmp)
  DEALLOCATE(wGP_tmp, xGP_tmp)
CASE('cell_volweight_mean')
  IF ((TRIM(InterpolationType).NE.'cell_volweight')) THEN
    ALLOCATE(CellVolWeightFac(0:PP_N))
    CellVolWeightFac(0:PP_N) = xGP(0:PP_N)
    CellVolWeightFac(0:PP_N) = (CellVolWeightFac(0:PP_N)+1.0)/2.0
  END IF

  ! Initialize sub-cell volumes around nodes
  CALL CalcCellLocNodeVolumes()
#if USE_MPI
  MPISharedSize = INT(4*nUniqueGlobalNodes,MPI_ADDRESS_KIND)*MPI_ADDRESS_KIND
  CALL Allocate_Shared(MPISharedSize,(/4,nUniqueGlobalNodes/),NodeSource_Shared_Win,NodeSource_Shared)
  CALL MPI_WIN_LOCK_ALL(0,NodeSource_Shared_Win,IERROR)
  NodeSource => NodeSource_Shared
  ALLOCATE(NodeSourceLoc(1:4,1:nUniqueGlobalNodes))

  IF(DoDielectricSurfaceCharge)THEN
    firstNode = INT(REAL( myComputeNodeRank   *nUniqueGlobalNodes)/REAL(nComputeNodeProcessors))+1
    lastNode  = INT(REAL((myComputeNodeRank+1)*nUniqueGlobalNodes)/REAL(nComputeNodeProcessors))

   ! Global, synchronized surface charge contribution (is added to NodeSource AFTER MPI synchronization)
    MPISharedSize = INT(nUniqueGlobalNodes,MPI_ADDRESS_KIND)*MPI_ADDRESS_KIND
    CALL Allocate_Shared(MPISharedSize,(/nUniqueGlobalNodes/),NodeSourceExt_Shared_Win,NodeSourceExt_Shared)
    CALL MPI_WIN_LOCK_ALL(0,NodeSourceExt_Shared_Win,IERROR)
    NodeSourceExt => NodeSourceExt_Shared
    !ALLOCATE(NodeSourceExtLoc(1:1,1:nUniqueGlobalNodes))
    IF(.NOT.DoRestart)THEN
      DO iNode=firstNode, lastNode
        NodeSourceExt(iNode) = 0.
      END DO
      CALL MPI_WIN_SYNC(NodeSourceExt_Shared_Win,IERROR)
      CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)
    END IF ! .NOT.DoRestart

   ! Local, non-synchronized surface charge contribution (is added to NodeSource BEFORE MPI synchronization)
    MPISharedSize = INT(nUniqueGlobalNodes,MPI_ADDRESS_KIND)*MPI_ADDRESS_KIND
    CALL Allocate_Shared(MPISharedSize,(/nUniqueGlobalNodes/),NodeSourceExtTmp_Shared_Win,NodeSourceExtTmp_Shared)
    CALL MPI_WIN_LOCK_ALL(0,NodeSourceExtTmp_Shared_Win,IERROR)
    NodeSourceExtTmp => NodeSourceExtTmp_Shared
    ALLOCATE(NodeSourceExtTmpLoc(1:nUniqueGlobalNodes))
    NodeSourceExtTmpLoc = 0.

    ! this array does not have to be initialized with zero
    ! DO iNode=firstNode, lastNode
    !   NodeSourceExtTmp(iNode) = 0.
    ! END DO
    !CALL MPI_WIN_SYNC(NodeSourceExtTmp_Shared_Win,IERROR)
    !CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)
  END IF ! DoDielectricSurfaceCharge



  IF ((myComputeNodeRank.EQ.0).AND.(nLeaderGroupProcs.GT.1)) THEN
    ALLOCATE(NodeMapping(0:nLeaderGroupProcs-1))
    ALLOCATE(NodeDepoMapping(0:nLeaderGroupProcs-1, 1:nUniqueGlobalNodes))
    NodeDepoMapping = .FALSE.

    DO iElem = 1, nComputeNodeTotalElems
      ! Loop all local nodes
      DO iNode = 1, 8
        NonUniqueNodeID = ElemNodeID_Shared(iNode,iElem)
        UniqueNodeID = NodeInfo_Shared(NonUniqueNodeID)

        ! Loop 1D array [offset + 1 : offset + NbrOfElems]
        ! (all CN elements that are connected to the local nodes)
        DO jElem = NodeToElemMapping(1,UniqueNodeID) + 1, NodeToElemMapping(1,UniqueNodeID) + NodeToElemMapping(2,UniqueNodeID)
          TestElemID = GetGlobalElemID(NodeToElemInfo(jElem))
          GlobalElemRank = ElemInfo_Shared(ELEM_RANK,TestElemID)
          ! find the compute node
          GlobalElemNode = INT(GlobalElemRank/nComputeNodeProcessors)
          ! check if element for this side is on the current compute-node. Alternative version to the check above
          IF (GlobalElemNode.NE.myLeaderGroupRank) NodeDepoMapping(GlobalElemNode, UniqueNodeID)  = .TRUE.
        END DO
      END DO
    END DO

    DO iProc = 0, nLeaderGroupProcs - 1
      IF (iProc.EQ.myLeaderGroupRank) CYCLE
      NodeMapping(iProc)%nRecvUniqueNodes = 0
      NodeMapping(iProc)%nSendUniqueNodes = 0
      CALL MPI_IRECV( NodeMapping(iProc)%nRecvUniqueNodes                       &
                  , 1                                                           &
                  , MPI_INTEGER                                                 &
                  , iProc                                                       &
                  , 666                                                         &
                  , MPI_COMM_LEADERS_SHARED                                     &
                  , RecvRequest(iProc)                                          &
                  , IERROR)
      DO iNode = 1, nUniqueGlobalNodes
        IF (NodeDepoMapping(iProc,iNode)) NodeMapping(iProc)%nSendUniqueNodes = NodeMapping(iProc)%nSendUniqueNodes + 1
      END DO
      CALL MPI_ISEND( NodeMapping(iProc)%nSendUniqueNodes                         &
                    , 1                                                           &
                    , MPI_INTEGER                                                 &
                    , iProc                                                       &
                    , 666                                                         &
                    , MPI_COMM_LEADERS_SHARED                                     &
                    , SendRequest(iProc)                                          &
                    , IERROR)
    END DO

    DO iProc = 0,nLeaderGroupProcs-1
      IF (iProc.EQ.myLeaderGroupRank) CYCLE
      CALL MPI_WAIT(SendRequest(iProc),MPISTATUS,IERROR)
      IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
      CALL MPI_WAIT(RecvRequest(iProc),MPISTATUS,IERROR)
      IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
    END DO

    DO iProc = 0,nLeaderGroupProcs-1
      IF (iProc.EQ.myLeaderGroupRank) CYCLE
      IF (NodeMapping(iProc)%nRecvUniqueNodes.GT.0) THEN
        ALLOCATE(NodeMapping(iProc)%RecvNodeUniqueGlobalID(1:NodeMapping(iProc)%nRecvUniqueNodes))
        ALLOCATE(NodeMapping(iProc)%RecvNodeSourceCharge(1:NodeMapping(iProc)%nRecvUniqueNodes))
        ALLOCATE(NodeMapping(iProc)%RecvNodeSourceCurrent(1:3,1:NodeMapping(iProc)%nRecvUniqueNodes))
        IF(DoDielectricSurfaceCharge) ALLOCATE(NodeMapping(iProc)%RecvNodeSourceExt(1:NodeMapping(iProc)%nRecvUniqueNodes))
        CALL MPI_IRECV( NodeMapping(iProc)%RecvNodeUniqueGlobalID                   &
                      , NodeMapping(iProc)%nRecvUniqueNodes                         &
                      , MPI_INTEGER                                                 &
                      , iProc                                                       &
                      , 666                                                         &
                      , MPI_COMM_LEADERS_SHARED                                     &
                      , RecvRequest(iProc)                                          &
                      , IERROR)
      END IF
      IF (NodeMapping(iProc)%nSendUniqueNodes.GT.0) THEN
        ALLOCATE(NodeMapping(iProc)%SendNodeUniqueGlobalID(1:NodeMapping(iProc)%nSendUniqueNodes))
        NodeMapping(iProc)%SendNodeUniqueGlobalID=-1
        ALLOCATE(NodeMapping(iProc)%SendNodeSourceCharge(1:NodeMapping(iProc)%nSendUniqueNodes))
        NodeMapping(iProc)%SendNodeSourceCharge=0.
        ALLOCATE(NodeMapping(iProc)%SendNodeSourceCurrent(1:3,1:NodeMapping(iProc)%nSendUniqueNodes))
        NodeMapping(iProc)%SendNodeSourceCurrent=0.
        IF(DoDielectricSurfaceCharge) ALLOCATE(NodeMapping(iProc)%SendNodeSourceExt(1:NodeMapping(iProc)%nSendUniqueNodes))
        SendNodeCount = 0
        DO iNode = 1, nUniqueGlobalNodes
          IF (NodeDepoMapping(iProc,iNode)) THEN
            SendNodeCount = SendNodeCount + 1
            NodeMapping(iProc)%SendNodeUniqueGlobalID(SendNodeCount) = iNode
          END IF
        END DO
        CALL MPI_ISEND( NodeMapping(iProc)%SendNodeUniqueGlobalID                   &
                      , NodeMapping(iProc)%nSendUniqueNodes                         &
                      , MPI_INTEGER                                                 &
                      , iProc                                                       &
                      , 666                                                         &
                      , MPI_COMM_LEADERS_SHARED                                     &
                      , SendRequest(iProc)                                          &
                      , IERROR)
      END IF
    END DO

    DO iProc = 0,nLeaderGroupProcs-1
      IF (iProc.EQ.myLeaderGroupRank) CYCLE
      IF (NodeMapping(iProc)%nSendUniqueNodes.GT.0) THEN
        CALL MPI_WAIT(SendRequest(iProc),MPISTATUS,IERROR)
        IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
      END IF
      IF (NodeMapping(iProc)%nRecvUniqueNodes.GT.0) THEN
        CALL MPI_WAIT(RecvRequest(iProc),MPISTATUS,IERROR)
        IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
      END IF
    END DO
  END IF
#else
  ALLOCATE(NodeSource(1:4,1:nUniqueGlobalNodes))
  IF(DoDielectricSurfaceCharge)THEN
    ALLOCATE(NodeSourceExt(1:nUniqueGlobalNodes))
    ALLOCATE(NodeSourceExtTmp(1:nUniqueGlobalNodes))
    NodeSourceExt    = 0.
    NodeSourceExtTmp = 0.
  END IF ! DoDielectricSurfaceCharge
#endif /*USE_MPI*/

  IF(DoDielectricSurfaceCharge)THEN
    ! Allocate and determine Vandermonde mapping from equidistant (visu) to NodeType node set
    ALLOCATE(Vdm_EQ_N(0:PP_N,0:1))
    CALL GetVandermonde(1, NodeTypeVISU, PP_N, NodeType, Vdm_EQ_N, modal=.FALSE.)
  END IF ! DoDielectricSurfaceCharge


!  ! Additional source for cell_volweight_mean (external or surface charge)
!  IF(DoDielectricSurfaceCharge)THEN
!    ALLOCATE(NodeSourceExt(1:nNodes))
!    NodeSourceExt = 0.0
!    ALLOCATE(NodeSourceExtTmp(1:nNodes))
!    NodeSourceExtTmp = 0.0
!  END IF ! DoDielectricSurfaceCharge
CASE('shape_function', 'shape_function_cc', 'shape_function_adaptive')
  alpha_sf = GETINT('PIC-shapefunction-alpha')
  dim_sf   = GETINT('PIC-shapefunction-dimension')
  ! Get shape function direction for 1D (the direction in which the charge will be distributed) and 2D (the direction in which the
  ! charge will be constant)
  dim_sf_dir = GETINT('PIC-shapefunction-direction')
  ! Distribute the charge over the volume (3D) or line (1D)/area (2D): default is TRUE
  sfDepo3D = GETLOGICAL('PIC-shapefunction-3D-deposition')

  ! Set shape function dimension (1D, 2D or 3D)
  CALL InitShapeFunctionDimensionalty()

  ! Set shape function radius in each cell or use global radius
  IF(TRIM(DepositionType).EQ.'shape_function_adaptive') THEN
    CALL InitShapeFunctionAdaptive()
    w_sf  = 1.0
  ELSE
    r2_sf = r_sf * r_sf  ! Radius squared
    r2_sf_inv = 1./r2_sf ! Inverse of radius squared
  END IF

  ! --- Init periodic case matrix for shape-function-deposition
  CALL InitPeriodicSFCaseMatrix()

  ! --- Set element flag for cycling already completed elements
#if USE_MPI
  ALLOCATE(ChargeSFDone(1:nComputeNodeTotalElems))
#else
  ALLOCATE(ChargeSFDone(1:nElems))
#endif /*USE_MPI*/

CASE DEFAULT
  CALL abort(&
  __STAMP__&
  ,'Unknown DepositionType in pic_depo.f90')
END SELECT

IF (PartSourceConstExists) THEN
  ALLOCATE(PartSourceConst(1:4,0:PP_N,0:PP_N,0:PP_N,nElems),STAT=ALLOCSTAT)
  IF (ALLOCSTAT.NE.0) THEN
    CALL abort(&
__STAMP__&
,'ERROR in pic_depo.f90: Cannot allocate PartSourceConst!')
  END IF
  PartSourceConst=0.
END IF

SWRITE(UNIT_stdOut,'(A)')' INIT PARTICLE DEPOSITION DONE!'

END SUBROUTINE InitializeDeposition


!===================================================================================================================================
!> Set dimension (1D, 2D or 3D) of shape function and calculate the corresponding line, area of volume to which the charge is to be
!> deposited. Output the average number of DOF that are captured by the shape function deposition kernel
!===================================================================================================================================
SUBROUTINE InitShapeFunctionDimensionalty()
! MODULES
USE MOD_Preproc
USE MOD_Globals            ,ONLY: UNIT_stdOut,MPIRoot,abort
USE MOD_PICDepo_Vars       ,ONLY: dim_sf,BetaFac,w_sf,r_sf,r2_sf,alpha_sf,dim_sf_dir,sfDepo3D,dim_sf_dir1,dim_sf_dir2
USE MOD_PICDepo_Vars       ,ONLY: DepositionType
USE MOD_Particle_Mesh_Vars ,ONLY: GEO,MeshVolume
USE MOD_ReadInTools        ,ONLY: PrintOption
USE MOD_Globals_Vars       ,ONLY: PI
USE MOD_Mesh_Vars          ,ONLY: nGlobalElems
USE MOD_PICDepo_Tools      ,ONLY: beta
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(32)             :: hilf_geo
CHARACTER(1)              :: hilf_dim
INTEGER                   :: nTotalDOF
REAL                      :: dimFactorSF
REAL                      :: VolumeShapeFunction
!===================================================================================================================================
! 1. Initialize auxiliary variables
hilf_geo='volume'
WRITE(UNIT=hilf_dim,FMT='(I0)') dim_sf

! 2. Set the scaling factor for the shape function depending on 1D, 2D or 3D shape function and how the charge is to be distributed
SELECT CASE (dim_sf)

  CASE (1) ! --- 1D shape function -------------------------------------------------------------------------------------------------
    ! Set perpendicular directions
    IF(dim_sf_dir.EQ.1)THEN ! Shape function deposits charge in x-direction
      dimFactorSF = (GEO%ymaxglob-GEO%yminglob)*(GEO%zmaxglob-GEO%zminglob)
    ELSE IF (dim_sf_dir.EQ.2)THEN ! Shape function deposits charge in y-direction
      dimFactorSF = (GEO%xmaxglob-GEO%xminglob)*(GEO%zmaxglob-GEO%zminglob)
    ELSE IF (dim_sf_dir.EQ.3)THEN ! Shape function deposits charge in z-direction
      dimFactorSF = (GEO%xmaxglob-GEO%xminglob)*(GEO%ymaxglob-GEO%yminglob)
    END IF

    ! Set prefix factor (not for shape_function_adaptive)
    IF(.NOT.TRIM(DepositionType).EQ.'shape_function_adaptive')THEN
      IF(sfDepo3D)THEN ! Distribute the charge over the volume (3D)
        w_sf = GAMMA(REAL(alpha_sf)+1.5)/(SQRT(PI)*r_sf*GAMMA(REAL(alpha_sf+1))*dimFactorSF)
      ELSE ! Distribute the charge over the line (1D)
        w_sf = GAMMA(REAL(alpha_sf)+1.5)/(SQRT(PI)*r_sf*GAMMA(REAL(alpha_sf+1)))
      END IF
    END IF ! .NOT.TRIM(DepositionType).EQ.'shape_function_adaptive'

    ! Set shape function length (3D volume)
    VolumeShapeFunction=2*r_sf*dimFactorSF
    ! Calculate number of 1D DOF (assume second and third direction with 1 cell layer and area given by dimFactorSF)
    nTotalDOF=nGlobalElems*(PP_N+1)

  CASE (2) ! --- 2D shape function -------------------------------------------------------------------------------------------------
    ! Set perpendicular direction
    IF(dim_sf_dir.EQ.1)THEN ! Shape function deposits charge in y-z-direction (const. in x)
      dimFactorSF = (GEO%xmaxglob-GEO%xminglob)
    ELSE IF (dim_sf_dir.EQ.2)THEN ! Shape function deposits charge in x-z-direction (const. in y)
      dimFactorSF = (GEO%ymaxglob-GEO%yminglob)
    ELSE IF (dim_sf_dir.EQ.3)THEN! Shape function deposits charge in x-y-direction (const. in z)
      dimFactorSF = (GEO%zmaxglob-GEO%zminglob)
    END IF

    ! Set prefix factor (not for shape_function_adaptive)
    IF(.NOT.TRIM(DepositionType).EQ.'shape_function_adaptive')THEN
      IF(sfDepo3D)THEN ! Distribute the charge over the volume (3D)
        w_sf = (REAL(alpha_sf)+1.0)/(PI*r2_sf*dimFactorSF)
      ELSE ! Distribute the charge over the area (2D)
        w_sf = (REAL(alpha_sf)+1.0)/(PI*r2_sf)
      END IF
    END IF ! .NOT.TRIM(DepositionType).EQ.'shape_function_adaptive'

    ! set the two perpendicular directions used for deposition
    dim_sf_dir1 = MERGE(1,2,dim_sf_dir.EQ.2)
    dim_sf_dir2 = MERGE(1,MERGE(3,3,dim_sf_dir.EQ.2),dim_sf_dir.EQ.3)
    SWRITE(UNIT_stdOut,'(A,I0,A,I0,A,I0,A)') ' Shape function 2D with const. distribution in dir ',dim_sf_dir,&
        ' and variable distrbution in ',dim_sf_dir1,' and ',dim_sf_dir2,' (1: x, 2: y and 3: z)'

    ! Set shape function length (3D volume)
    VolumeShapeFunction=PI*(r_sf**2)*dimFactorSF
    ! Calculate number of 2D DOF (assume third direction with 1 cell layer and width dimFactorSF)
    nTotalDOF=nGlobalElems*(PP_N+1)**2

  CASE (3) ! --- 3D shape function -------------------------------------------------------------------------------------------------
    ! Set prefix factor (not for shape_function_adaptive)
    IF(.NOT.TRIM(DepositionType).EQ.'shape_function_adaptive')THEN
      BetaFac = beta(1.5, REAL(alpha_sf) + 1.)
      w_sf = 1./(2. * BetaFac * REAL(alpha_sf) + 2 * BetaFac) * (REAL(alpha_sf) + 1.)/(PI*(r_sf**3))
    END IF ! .NOT.TRIM(DepositionType).EQ.'shape_function_adaptive'

  CASE DEFAULT
    CALL abort(__STAMP__,'Shape function dimensio must be 1, 2 or 3')
END SELECT

! 3. Output info on how the shape function deposits the charge
IF(.NOT.sfDepo3D.AND.dim_sf.EQ.1)THEN
  hilf_geo='line'
ELSEIF(.NOT.sfDepo3D.AND.dim_sf.EQ.2)THEN
  hilf_geo='area'
END IF

SWRITE(UNIT_stdOut,'(A)') ' The complete charge is '//TRIM(hilf_geo)//' distributed (via '//TRIM(hilf_dim)//'D shape function)'

IF(.NOT.sfDepo3D)THEN
  SWRITE(UNIT_stdOut,'(A)') ' Note that the integral of the charge density over the mesh volume is larger than the complete charge'
  SWRITE(UNIT_stdOut,'(A)') ' because the charge is spread out over either a line (1D shape function) or an area (2D shape function)!'
END IF

! 4. Output info regarding charge distribution and points per shape function resolution
IF(.NOT.TRIM(DepositionType).EQ.'shape_function_adaptive')THEN
  ASSOCIATE(nTotalDOFin3D             => nGlobalElems*(PP_N+1)**3 ,&
            VolumeShapeFunctionSphere => 4./3.*PI*r_sf**3         )

    ! Output shape function volume
    IF(dim_sf.EQ.1)THEN
      CALL PrintOption('Shape function volume (corresponding to a cuboid in 3D)'  , 'CALCUL.', RealOpt=VolumeShapeFunction)
    ELSEIF(dim_sf.EQ.2)THEN
      CALL PrintOption('Shape function volume (corresponding to a cylinder in 3D)', 'CALCUL.', RealOpt=VolumeShapeFunction)
    ELSE
      VolumeShapeFunction = VolumeShapeFunctionSphere
      CALL PrintOption('Shape function volume (corresponding to a sphere in 3D)'  , 'CALCUL.', RealOpt=VolumeShapeFunction)
    END IF

    ! Sanity check: Shape function volume is not allowed to be larger than the complete mesh simulation domain
    IF(MPIRoot)THEN
      IF(VolumeShapeFunction.GT.MeshVolume)THEN
        CALL PrintOption('Mesh volume ('//TRIM(hilf_dim)//')', 'CALCUL.' , RealOpt=MeshVolume)
        WRITE(UNIT_stdOut,'(A)') ' Maybe wrong perpendicular direction (PIC-shapefunction-direction)?'
        CALL abort(__STAMP__,'ShapeFunctionVolume > MeshVolume ('//TRIM(hilf_dim)//' shape function)')
      END IF
    END IF

    ! Display 1D or 2D deposition info
    IF(dim_sf.NE.3)THEN
      CALL PrintOption('Average DOFs in Shape-Function '//TRIM(hilf_geo)//' ('//TRIM(hilf_dim)//')' , 'CALCUL.' , RealOpt=&
          REAL(nTotalDOF)*VolumeShapeFunction/MeshVolume)
    END IF ! dim_sf.NE.3

    CALL PrintOption('Average DOFs in Shape-Function (corresponding 3D sphere)' , 'CALCUL.' , RealOpt=&
        REAL(nTotalDOFin3D)*VolumeShapeFunctionSphere/MeshVolume)
  END ASSOCIATE
END IF ! .NOT.TRIM(DepositionType).EQ.'shape_function_adaptive'


END SUBROUTINE InitShapeFunctionDimensionalty


!===================================================================================================================================
!> Calculate the shape function radius for each element depending on the neighbouring element sizes and the own element size
!===================================================================================================================================
SUBROUTINE InitShapeFunctionAdaptive()
! MODULES
USE MOD_Preproc
USE MOD_Globals            ,ONLY: UNIT_stdOut,MPIRoot,abort,IERROR,MPI_ADDRESS_KIND,VECNORM
USE MOD_PICDepo_Vars       ,ONLY: SFAdaptiveDOF,SFElemr2_Shared,SFElemr2_Shared_Win
USE MOD_ReadInTools        ,ONLY: GETREAL
USE MOD_Particle_Mesh_Vars ,ONLY: ElemNodeID_Shared,NodeInfo_Shared
USE MOD_Mesh_Tools         ,ONLY: GetCNElemID
USE MOD_Globals_Vars       ,ONLY: PI
USE MOD_Particle_Mesh_Vars ,ONLY: ElemMidPoint_Shared,ElemToElemMapping,ElemToElemInfo
USE MOD_Mesh_Tools         ,ONLY: GetGlobalElemID
USE MOD_MPI_Shared_Vars    ,ONLY: nComputeNodeTotalElems,nComputeNodeProcessors,myComputeNodeRank
USE MOD_MPI_Shared_Vars    ,ONLY: MPI_COMM_SHARED
USE MOD_Particle_Mesh_Vars ,ONLY: NodeCoords_Shared
USE MOD_MPI_Shared
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: UniqueNodeID,NonUniqueNodeID,iNode,NeighUniqueNodeID
REAL                           :: middist,SFDepoScaling
LOGICAL                        :: ElemDone
INTEGER                        :: ppp,globElemID
REAL                           :: r_sf_tmp
INTEGER                        :: iElem,firstElem,lastElem,jNode,NbElemID,NeighNonUniqueNodeID
INTEGER(KIND=MPI_ADDRESS_KIND) :: MPISharedSize
!===================================================================================================================================
! Set the number of DOF/SF
SFAdaptiveDOF = GETREAL('PIC-shapefunction-adaptive-DOF')
IF(SFAdaptiveDOF.GT.(4./3.)*PI*(PP_N+1)**3)THEN
  SWRITE(UNIT_StdOut,*) "         PIC-shapefunction-adaptive-DOF =", SFAdaptiveDOF
  SWRITE(UNIT_StdOut,*) "Maximum allowed is 4./3.*PI*(PP_N+1)**3 =", (4./3.)*PI*(PP_N+1)**3
  SWRITE(UNIT_StdOut,*) "Reduce the number of DOF/SF in order to have no DOF outside of the deposition range (neighbour elems)"
  SWRITE(UNIT_StdOut,*) "Set a value lower or equal to than the maximum for a given polynomial degree N\n"
  SWRITE(UNIT_StdOut,*) "         N:     1      2      3      4      5       6       7"
  SWRITE(UNIT_StdOut,*) "  Max. DOF:    33    113    268    523    904    1436    2144"
  CALL abort(__STAMP__,'PIC-shapefunction-adaptive-DOF > 4./3.*PI*(PP_N+1)**3 is not allowed')
ELSE
  SFDepoScaling = (3.*SFAdaptiveDOF/(4.*PI))**(1./3.)
END IF

#if USE_MPI
firstElem = INT(REAL( myComputeNodeRank   *nComputeNodeTotalElems)/REAL(nComputeNodeProcessors))+1
lastElem  = INT(REAL((myComputeNodeRank+1)*nComputeNodeTotalElems)/REAL(nComputeNodeProcessors))

MPISharedSize = INT(2*nComputeNodeTotalElems,MPI_ADDRESS_KIND)*MPI_ADDRESS_KIND
CALL Allocate_Shared(MPISharedSize,(/2,nComputeNodeTotalElems/),SFElemr2_Shared_Win,SFElemr2_Shared)
CALL MPI_WIN_LOCK_ALL(0,SFElemr2_Shared_Win,IERROR)
#else
ALLOCATE(SFElemr2_Shared(1:2,1:nElems))
firstElem = 1
lastElem  = nElems
#endif  /*USE_MPI*/
#if USE_MPI
IF (myComputeNodeRank.EQ.0) THEN
#endif
  SFElemr2_Shared = HUGE(1.)
#if USE_MPI
END IF
CALL MPI_WIN_SYNC(SFElemr2_Shared_Win,IERROR)
CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)
#endif
DO iElem = firstElem,lastElem
  ElemDone = .FALSE.

  ! Calculate the average distance from the ElemMidPoint to all 8 corners
  middist = 0.0
  DO iNode = 1, 8
    NonUniqueNodeID = ElemNodeID_Shared(iNode,iElem)
    middist = middist + VECNORM(ElemMidPoint_Shared(1:3,iElem)-NodeCoords_Shared(1:3,NonUniqueNodeID))
  END DO
  ! Scale the influence of my own cell (starting from 8. and the higher the number, the smaller the weight of the own cell)
  middist = middist / 10.524 ! 10.524 is tuned to achieve a radius of r = 1.0*L (when using 2.0 / (PP_N+1.) as scaling factor),
  !  where L is the cell length of a cubic Cartesian element

  DO ppp = 1,ElemToElemMapping(2,iElem)
    globElemID = GetGlobalElemID(ElemToElemInfo(ElemToElemMapping(1,iElem)+ppp))
    NbElemID = GetCNElemID(globElemID)
    Nodeloop: DO jNode = 1, 8
      NeighNonUniqueNodeID = ElemNodeID_Shared(jNode,NbElemID)
      NeighUniqueNodeID = NodeInfo_Shared(NeighNonUniqueNodeID)
      DO iNode = 1, 8
        NonUniqueNodeID = ElemNodeID_Shared(iNode,iElem)
        UniqueNodeID = NodeInfo_Shared(NonUniqueNodeID)
        IF (UniqueNodeID.EQ.NeighUniqueNodeID) CYCLE Nodeloop
      END DO
      ElemDone =.TRUE.
      r_sf_tmp = VECNORM(ElemMidPoint_Shared(1:3,iElem)-NodeCoords_Shared(1:3,NeighNonUniqueNodeID))
      IF (r_sf_tmp.LT.SFElemr2_Shared(1,iElem)) SFElemr2_Shared(1,iElem) = r_sf_tmp
    END DO Nodeloop
  END DO
  IF (.NOT.ElemDone) THEN
    DO iNode = 1, 8
      NonUniqueNodeID = ElemNodeID_Shared(iNode,iElem)
      r_sf_tmp = VECNORM(ElemMidPoint_Shared(1:3,iElem)-NodeCoords_Shared(1:3,NonUniqueNodeID))
      IF (r_sf_tmp.LT.SFElemr2_Shared(1,iElem)) SFElemr2_Shared(1,iElem) = r_sf_tmp
    END DO
  END IF
  ! Scale the radius so that it reaches at most the neighbouring cells but no further (all neighbours of the 8 corner nodes)
  SFElemr2_Shared(1,iElem) = (SFElemr2_Shared(1,iElem) - middist) * SFDepoScaling / (PP_N+1.)
  SFElemr2_Shared(2,iElem) = SFElemr2_Shared(1,iElem)**2
END DO
#if USE_MPI
CALL MPI_WIN_SYNC(SFElemr2_Shared_Win,IERROR)
CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)
#endif

END SUBROUTINE InitShapeFunctionAdaptive


!===================================================================================================================================
!> Fill PeriodicSFCaseMatrix when using shape function deposition in combination with periodic boundaries
!===================================================================================================================================
SUBROUTINE InitPeriodicSFCaseMatrix()
! MODULES
USE MOD_Globals            ,ONLY: MPIRoot,UNIT_StdOut
USE MOD_Particle_Mesh_Vars ,ONLY: PeriodicSFCaseMatrix,NbrOfPeriodicSFCases
USE MOD_PICDepo_Vars       ,ONLY: dim_sf,dim_periodic_vec1,dim_periodic_vec2,dim_sf_dir1,dim_sf_dir2
USE MOD_Particle_Mesh_Vars ,ONLY: GEO
USE MOD_ReadInTools        ,ONLY: PrintOption
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: I,J
!===================================================================================================================================
IF (GEO%nPeriodicVectors.LE.0) THEN

  ! Set defaults and return in non-periodic case
  NbrOfPeriodicSFCases = 1
  ALLOCATE(PeriodicSFCaseMatrix(1:1,1:3))
  PeriodicSFCaseMatrix(:,:) = 0

ELSE

  ! Build case matrix:
  ! Particles may move in more periodic directions than their charge is deposited, e.g., fully periodic in combination with
  ! 1D shape function
  NbrOfPeriodicSFCases = 3**dim_sf

  ALLOCATE(PeriodicSFCaseMatrix(1:NbrOfPeriodicSFCases,1:3))
  PeriodicSFCaseMatrix(:,:) = 0
  IF (dim_sf.EQ.1) THEN
    PeriodicSFCaseMatrix(1,1) = 1
    PeriodicSFCaseMatrix(3,1) = -1
  END IF
  IF (dim_sf.EQ.2) THEN
    PeriodicSFCaseMatrix(1:3,1) = 1
    PeriodicSFCaseMatrix(7:9,1) = -1
    DO I = 1,3
      PeriodicSFCaseMatrix(I*3-2,2) = 1
      PeriodicSFCaseMatrix(I*3,2) = -1
    END DO
  END IF
  IF (dim_sf.EQ.3) THEN
    PeriodicSFCaseMatrix(1:9,1) = 1
    PeriodicSFCaseMatrix(19:27,1) = -1
    DO I = 1,3
      PeriodicSFCaseMatrix(I*9-8:I*9-6,2) = 1
      PeriodicSFCaseMatrix(I*9-2:I*9,2) = -1
      DO J = 1,3
        PeriodicSFCaseMatrix((J*3-2)+(I-1)*9,3) = 1
        PeriodicSFCaseMatrix((J*3)+(I-1)*9,3) = -1
      END DO
    END DO
  END IF

  ! Define which of the periodic vectors are used for 2D shape function and display info
  IF(dim_sf.EQ.2)THEN
    IF(GEO%nPeriodicVectors.EQ.1)THEN
      dim_periodic_vec1 = 1
      dim_periodic_vec2 = 0
    ELSEIF(GEO%nPeriodicVectors.EQ.2)THEN
      dim_periodic_vec1 = 1
      dim_periodic_vec2 = 2
    ELSEIF(GEO%nPeriodicVectors.EQ.3)THEN
      dim_periodic_vec1 = dim_sf_dir1
      dim_periodic_vec2 = dim_sf_dir2
    END IF ! GEO%nPeriodicVectors.EQ.1
    CALL PrintOption('Dimension of 1st periodic vector for 2D shape function','INFO',IntOpt=dim_periodic_vec1)
    SWRITE(UNIT_StdOut,*) "1st PeriodicVector =", GEO%PeriodicVectors(1:3,dim_periodic_vec1)
    CALL PrintOption('Dimension of 2nd periodic vector for 2D shape function','INFO',IntOpt=dim_periodic_vec2)
    SWRITE(UNIT_StdOut,*) "1st PeriodicVector =", GEO%PeriodicVectors(1:3,dim_periodic_vec2)
  END IF ! dim_sf.EQ.2

END IF

END SUBROUTINE InitPeriodicSFCaseMatrix


SUBROUTINE Deposition(doParticle_In)
!============================================================================================================================
! This subroutine performs the deposition of the particle charge and current density to the grid
! following list of distribution methods are implemented
! - shape function       (only one type implemented)
! useVMPF added, therefore, this routine contains automatically the use of variable mpfs
!============================================================================================================================
! USE MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Particle_Analyze_Vars ,ONLY: DoVerifyCharge,PartAnalyzeStep
USE MOD_Particle_Vars
USE MOD_PICDepo_Vars
USE MOD_PICDepo_Method        ,ONLY: DepositionMethod
USE MOD_PIC_Analyze           ,ONLY: VerifyDepositedCharge
USE MOD_TimeDisc_Vars         ,ONLY: iter
#if USE_MPI
USE MOD_MPI_Shared_Vars       ,ONLY: myComputeNodeRank,MPI_COMM_SHARED
#endif  /*USE_MPI*/
!-----------------------------------------------------------------------------------------------------------------------------------
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT variable declaration
LOGICAL,INTENT(IN),OPTIONAL      :: doParticle_In(1:PDM%ParticleVecLength) ! TODO: definition of this variable
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT variable declaration
!-----------------------------------------------------------------------------------------------------------------------------------
! Local variable declaration
!-----------------------------------------------------------------------------------------------------------------------------------
!============================================================================================================================
! Return, if no deposition is required
IF(.NOT.DoDeposition) RETURN

#if USE_MPI
IF (myComputeNodeRank.EQ.0) THEN
#endif  /*USE_MPI*/
  PartSource = 0.0
#if USE_MPI
END IF
CALL MPI_WIN_SYNC(PartSource_Shared_Win, IERROR)
CALL MPI_BARRIER(MPI_COMM_SHARED, IERROR)
#endif  /*USE_MPI*/

IF(PRESENT(doParticle_In)) THEN
  CALL DepositionMethod(doParticle_In)
ELSE
  CALL DepositionMethod()
END IF

IF(MOD(iter,PartAnalyzeStep).EQ.0) THEN
  IF(DoVerifyCharge) CALL VerifyDepositedCharge()
END IF
RETURN
END SUBROUTINE Deposition


SUBROUTINE FinalizeDeposition()
!----------------------------------------------------------------------------------------------------------------------------------!
! finalize pic deposition
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Dielectric_Vars    ,ONLY: DoDielectricSurfaceCharge
USE MOD_Particle_Mesh_Vars ,ONLY: GEO,PeriodicSFCaseMatrix
USE MOD_PICDepo_Vars
#if USE_MPI
USE MOD_MPI_Shared_vars    ,ONLY: MPI_COMM_SHARED
USE MOD_MPI_Shared
#endif
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
SDEALLOCATE(PartSourceConst)
SDEALLOCATE(PartSourceOld)
SDEALLOCATE(GaussBorder)
SDEALLOCATE(Vdm_EquiN_GaussN)
SDEALLOCATE(Knots)
SDEALLOCATE(GaussBGMIndex)
SDEALLOCATE(GaussBGMFactor)
SDEALLOCATE(GEO%PeriodicBGMVectors)
SDEALLOCATE(BGMSource)
SDEALLOCATE(GPWeight)
SDEALLOCATE(ElemRadius2_sf)
SDEALLOCATE(Vdm_NDepo_GaussN)
SDEALLOCATE(DDMassInv)
SDEALLOCATE(XiNDepo)
SDEALLOCATE(swGPNDepo)
SDEALLOCATE(wBaryNDepo)
SDEALLOCATE(NDepochooseK)
SDEALLOCATE(tempcharge)
SDEALLOCATE(CellVolWeightFac)
SDEALLOCATE(CellVolWeight_Volumes)
SDEALLOCATE(ChargeSFDone)
SDEALLOCATE(PeriodicSFCaseMatrix)

#if USE_MPI
SDEALLOCATE(NodeSourceLoc)
SDEALLOCATE(PartSourceProc)
SDEALLOCATE(NodeMapping)

! First, free every shared memory window. This requires MPI_BARRIER as per MPI3.1 specification
CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)

IF(DoDeposition)THEN
  CALL UNLOCK_AND_FREE(PartSource_Shared_Win)

  ! Deposition-dependent arrays
  SELECT CASE(TRIM(DepositionType))
  CASE('cell_volweight_mean')
    CALL UNLOCK_AND_FREE(NodeSource_Shared_Win)
    CALL UNLOCK_AND_FREE(NodeVolume_Shared_Win)

    ! Surface charging arrays
    IF(DoDielectricSurfaceCharge) CALL UNLOCK_AND_FREE(NodeSourceExt_Shared_Win)
  CASE('shape_function_adaptive')
    CALL UNLOCK_AND_FREE(SFElemr2_Shared_Win)
  END SELECT

  CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)

  ADEALLOCATE(NodeSource_Shared)
  ADEALLOCATE(NodeVolume_Shared)
      ADEALLOCATE(NodeSourceExt_Shared)
END IF ! DoDeposition

! Then, free the pointers or arrays
ADEALLOCATE(PartSource_Shared)
#endif /*USE_MPI*/

! Then, free the pointers or arrays
ADEALLOCATE(PartSource)

! Deposition-dependent pointers/arrays
SELECT CASE(TRIM(DepositionType))
  CASE('cell_volweight_mean')
    ADEALLOCATE(NodeSource)
    ! Surface charging pointers/arrays
    IF(DoDielectricSurfaceCharge)THEN
      ADEALLOCATE(NodeSourceExt)
    END IF ! DoDielectricSurfaceCharge
#if USE_MPI
    ADEALLOCATE(NodeSource_Shared)
#endif /*USE_MPI*/
  CASE('shape_function_adaptive')
    ADEALLOCATE(SFElemr2_Shared)
END SELECT

END SUBROUTINE FinalizeDeposition

END MODULE MOD_PICDepo
