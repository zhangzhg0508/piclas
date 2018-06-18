#include "boltzplatz.h"

MODULE MOD_ESBGK_Adaptation
!===================================================================================================================================
!> description
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE ESBGK_octree_adapt
  MODULE PROCEDURE ESBGK_octree_adapt
END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: ESBGK_octree_adapt!, ESBGKSplitCells
!===================================================================================================================================

CONTAINS

SUBROUTINE ESBGK_octree_adapt(iElem)
!===================================================================================================================================
!> Pairing subroutine for octree and nearest neighbour, decides whether to create a new octree node 
!> or start nearest neighbour search
!===================================================================================================================================
! MODULES
USE MOD_DSMC_Vars              ,ONLY: tTreeNode, DSMC, ElemNodeVol
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Particle_Vars          ,ONLY: PEM, PartState, PartPosRef
USE MOD_Particle_Tracking_vars ,ONLY: DoRefMapping
USE MOD_ESBGK_CollOperator     ,ONLY: ESBGK_CollisionOperatorOctree
USE MOD_ESBGK_Vars             ,ONLY: BGKMinPartPerCell, BGKDoAveraging, ElemNodeAveraging, BGKAveragingLength
USE MOD_Eval_xyz               ,ONLY: Eval_XYZ_ElemCheck
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)           :: iElem
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                       :: iPart, iLoop, nPart
REAL                          :: vBulk(3)
REAL, ALLOCATABLE             :: MappedPartStates(:,:)
TYPE(tTreeNode), POINTER      :: TreeNode
!===================================================================================================================================
nPart = PEM%pNumber(iElem)
IF ((nPart.EQ.0).OR.(nPart.EQ.1)) THEN
  RETURN
END IF

NULLIFY(TreeNode)

ALLOCATE(TreeNode)
ALLOCATE(TreeNode%iPartIndx_Node(nPart)) ! List of particles in the cell neccessary for stat pairing
TreeNode%iPartIndx_Node(1:nPart) = 0

vBulk(1:3) = 0.0
iPart = PEM%pStart(iElem)                         ! create particle index list for pairing
DO iLoop = 1, nPart
  TreeNode%iPartIndx_Node(iLoop) = iPart
  vBulk(1:3)  =  vBulk(1:3) + PartState(iPart,4:6)
  iPart = PEM%pNext(iPart)
END DO
vBulk = vBulk / nPart

! Octree can only performed if nPart is greater than the defined value (default=20), otherwise nearest neighbour pairing
IF(nPart.GE.(2.*BGKMinPartPerCell)) THEN
  ! Additional check afterwards if nPart is greater than PartNumOctreeNode (default=80) or the mean free path is less than
  ! the side length of a cube (approximation) with same volume as the actual cell -> octree
  ALLOCATE(TreeNode%MappedPartStates(1:nPart, 1:3))
  TreeNode%PNum_Node = nPart
  iPart = PEM%pStart(iElem)                         ! create particle index list for pairing
  IF (DoRefMapping) THEN
    DO iLoop = 1, nPart
      TreeNode%MappedPartStates(iLoop,1:3)=PartPosRef(1:3,iPart)
      iPart = PEM%pNext(iPart)
    END DO
  ELSE ! position in reference space [-1,1] has to be computed
    DO iLoop = 1, nPart
      CALL Eval_XYZ_ElemCheck(PartState(iPart,1:3),TreeNode%MappedPartStates(iLoop,1:3),iElem)
      !CALL GeoCoordToMap(PartState(iPart,1:3), TreeNode%MappedPartStates(iLoop,1:3), iElem)
      iPart = PEM%pNext(iPart)
    END DO
  END IF ! DoRefMapping
  TreeNode%NodeDepth = 1
  TreeNode%MidPoint(1:3) = (/0.0,0.0,0.0/)
  IF (BGKDoAveraging) THEN
    CALL AddESBGKOctreeNode(TreeNode, iElem, ElemNodeVol(iElem)%Root, ElemNodeAveraging(iElem)%Root)
  ELSE
    CALL AddESBGKOctreeNode(TreeNode, iElem, ElemNodeVol(iElem)%Root)
  END IF
  DEALLOCATE(TreeNode%MappedPartStates)
ELSE
  IF (BGKDoAveraging) THEN
    CALL ESBGK_CollisionOperatorOctree(TreeNode%iPartIndx_Node, nPart, &
              iElem, GEO%Volume(iElem), vBulk, &
             ElemNodeAveraging(iElem)%Root%AverageValues(1:5,1:BGKAveragingLength), &
             CorrectStep = ElemNodeAveraging(iElem)%Root%CorrectStep)
  ELSE
    CALL ESBGK_CollisionOperatorOctree(TreeNode%iPartIndx_Node, nPart &
                            , iElem, GEO%Volume(iElem), vBulk)
  END IF
END IF

DEALLOCATE(TreeNode%iPartIndx_Node)
DEALLOCATE(TreeNode)

END SUBROUTINE ESBGK_octree_adapt


RECURSIVE SUBROUTINE AddESBGKOctreeNode(TreeNode, iElem, NodeVol, Averaging)
!===================================================================================================================================
!> Adds additional octree node/branch (fancy)
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_DSMC_Vars            ,ONLY: tTreeNode, DSMC, tNodeVolume
USE MOD_Particle_Vars        ,ONLY: nSpecies, PartSpecies, PartState
USE MOD_DSMC_Vars            ,ONLY: ElemNodeVol
USE MOD_ESBGK_CollOperator   ,ONLY: ESBGK_CollisionOperatorOctree
USE MOD_DSMC_ParticlePairing ,ONLY: DSMC_CalcSubNodeVolumes
USE MOD_ESBGK_Vars           ,ONLY: BGKMinPartPerCell,tNodeAverage, ElemNodeAveraging, BGKDoAveraging, BGKDoAveragingCorrect
USE MOD_ESBGK_Vars           ,ONLY: BGKAveragingLength
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)                                 :: iElem
TYPE(tTreeNode),INTENT(IN), POINTER                 :: TreeNode
TYPE(tNodeVolume),INTENT(IN), POINTER               :: NodeVol
TYPE(tNodeAverage),INTENT(INOUT), POINTER, OPTIONAL :: Averaging
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                      :: iPart, iLoop, iPartIndx, localDepth, SpecPartNum(nSpecies), iLoop2
INTEGER, ALLOCATABLE         :: iPartIndx_ChildNode(:,:)
REAL, ALLOCATABLE            :: MappedPart_ChildNode(:,:,:)
INTEGER                      :: PartNumChildNode(8), MergeTemp(8), NodeAveragingCorrect(8)
REAL                         :: NodeVolumeTemp(8), vBulk(3,8), NodeAveragingTemp(8,5,BGKAveragingLength)
LOGICAL                      :: ForceESBGK
!===================================================================================================================================
IF (TreeNode%PNum_Node.LE.8.*BGKMinPartPerCell) THEN
  ForceESBGK = .TRUE.
ELSE
  ForceESBGK = .FALSE.
END IF
ALLOCATE(iPartIndx_ChildNode(8,TreeNode%PNum_Node))
ALLOCATE(MappedPart_ChildNode(8,TreeNode%PNum_Node,3))
PartNumChildNode(:) = 0
IF (ABS(TreeNode%MidPoint(1)) .EQ. 1.0) THEN
  CALL Abort(&
__STAMP__&
,'ERROR in Octree Pairing: Too many branches, machine precision reached')
END IF
!         Numbering of the 8 ChildNodes of the Octree
!          __________
!         /    /    /|   |z
!        /  7 / 6  / |   |
!       /----/----/|6|   |
!      /_3__/_2__/ |/|   |______Y
!     |    |    |2 |5|   /
!     | 3  | 2  |/ |/   /
!     |----|----|1 /   /x
!     | 4  | 1  | /
!     |____|____|/

! particle to Octree ChildNode sorting
vBulk = 0.0
DO iPart=1,TreeNode%PNum_Node
  iPartIndx = TreeNode%iPartIndx_Node(iPart)
  IF ((TreeNode%MappedPartStates(iPart,1).GE.TreeNode%MidPoint(1)) &
      .AND.(TreeNode%MappedPartStates(iPart,2).GE.TreeNode%MidPoint(2)) &
      .AND.(TreeNode%MappedPartStates(iPart,3).LE.TreeNode%MidPoint(3))) THEN
    PartNumChildNode(1) = PartNumChildNode(1) + 1
    iPartIndx_ChildNode(1,PartNumChildNode(1)) = iPartIndx
    vBulk(1:3,1) = vBulk(1:3,1) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(1,PartNumChildNode(1),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  ELSE IF((TreeNode%MappedPartStates(iPart,1).GE.TreeNode%MidPoint(1)) &
      .AND.(TreeNode%MappedPartStates(iPart,2).GE.TreeNode%MidPoint(2))) THEN
    PartNumChildNode(2) = PartNumChildNode(2) + 1
    iPartIndx_ChildNode(2,PartNumChildNode(2)) = iPartIndx
    vBulk(1:3,2) = vBulk(1:3,2) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(2,PartNumChildNode(2),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  ELSE IF((TreeNode%MappedPartStates(iPart,1).GE.TreeNode%MidPoint(1)) &
      .AND.(TreeNode%MappedPartStates(iPart,3).GE.TreeNode%MidPoint(3))) THEN
    PartNumChildNode(3) = PartNumChildNode(3) + 1
    iPartIndx_ChildNode(3,PartNumChildNode(3)) = iPartIndx
    vBulk(1:3,3) = vBulk(1:3,3) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(3,PartNumChildNode(3),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  ELSE IF (TreeNode%MappedPartStates(iPart,1).GE.TreeNode%MidPoint(1)) THEN
    PartNumChildNode(4) = PartNumChildNode(4) + 1
    iPartIndx_ChildNode(4,PartNumChildNode(4)) = iPartIndx
    vBulk(1:3,4) = vBulk(1:3,4) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(4,PartNumChildNode(4),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  ELSE IF((TreeNode%MappedPartStates(iPart,2).GE.TreeNode%MidPoint(2)) &
      .AND.(TreeNode%MappedPartStates(iPart,3).LE.TreeNode%MidPoint(3))) THEN
    PartNumChildNode(5) = PartNumChildNode(5) + 1
    iPartIndx_ChildNode(5,PartNumChildNode(5)) = iPartIndx
    vBulk(1:3,5) = vBulk(1:3,5) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(5,PartNumChildNode(5),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  ELSE IF (TreeNode%MappedPartStates(iPart,2).GE.TreeNode%MidPoint(2)) THEN
    PartNumChildNode(6) = PartNumChildNode(6) + 1
    iPartIndx_ChildNode(6,PartNumChildNode(6)) = iPartIndx
    vBulk(1:3,6) = vBulk(1:3,6) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(6,PartNumChildNode(6),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  ELSE IF (TreeNode%MappedPartStates(iPart,3).GE.TreeNode%MidPoint(3)) THEN
    PartNumChildNode(7) = PartNumChildNode(7) + 1
    iPartIndx_ChildNode(7,PartNumChildNode(7)) = iPartIndx
    vBulk(1:3,7) = vBulk(1:3,7) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(7,PartNumChildNode(7),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  ELSE
    PartNumChildNode(8) = PartNumChildNode(8) + 1
    iPartIndx_ChildNode(8,PartNumChildNode(8)) = iPartIndx
    vBulk(1:3,8) = vBulk(1:3,8) + PartState(iPartIndx,4:6)
    MappedPart_ChildNode(8,PartNumChildNode(8),1:3) = TreeNode%MappedPartStates(iPart,1:3)
  END IF
END DO

IF(ANY(PartNumChildNode.LT.BGKMinPartPerCell)) ForceESBGK = .TRUE.

IF((.NOT.ASSOCIATED(NodeVol)).OR.(.NOT.ASSOCIATED(NodeVol%SubNode1))) THEN
  localDepth = TreeNode%NodeDepth
  CALL DSMC_CalcSubNodeVolumes(iElem, localDepth, ElemNodeVol(iElem)%Root)
END IF

NodeVolumeTemp(1) = NodeVol%SubNode1%Volume
NodeVolumeTemp(2) = NodeVol%SubNode2%Volume
NodeVolumeTemp(3) = NodeVol%SubNode3%Volume
NodeVolumeTemp(4) = NodeVol%SubNode4%Volume
NodeVolumeTemp(5) = NodeVol%SubNode5%Volume
NodeVolumeTemp(6) = NodeVol%SubNode6%Volume
NodeVolumeTemp(7) = NodeVol%SubNode7%Volume
NodeVolumeTemp(8) = NodeVol%SubNode8%Volume

IF (BGKDoAveraging) THEN
  IF (.NOT.ASSOCIATED(Averaging%SubNode1)) THEN
    CALL BGK_AllocateAveragingNode(Averaging)
  END IF
END IF

IF(ForceESBGK) THEN
  DO iLoop = 1, 7
    IF (PartNumChildNode(iLoop).LT.BGKMinPartPerCell) THEN
      DO iPart=1, PartNumChildNode(iLoop)
        iPartIndx_ChildNode(iLoop+1,PartNumChildNode(iLoop+1)+iPart) = iPartIndx_ChildNode(iLoop,iPart)
        MappedPart_ChildNode(iLoop+1,PartNumChildNode(iLoop+1)+iPart,1:3) = MappedPart_ChildNode(iLoop,iPart,1:3)
        vBulk(1:3,iLoop+1) = vBulk(1:3,iLoop+1) + PartState(iPartIndx_ChildNode(iLoop,iPart),4:6)
      END DO
      PartNumChildNode(iLoop+1) = PartNumChildNode(iLoop+1) + PartNumChildNode(iLoop)
      PartNumChildNode(iLoop) = 0
      NodeVolumeTemp(iLoop+1) = NodeVolumeTemp(iLoop+1) + NodeVolumeTemp(iLoop)
      NodeVolumeTemp(iLoop) = 0.0
    END IF
  END DO
  IF (PartNumChildNode(8).LT.BGKMinPartPerCell) THEN
    DO iLoop = 1, 7
     iLoop2 = iLoop
     IF (PartNumChildNode(iLoop).GT.0) EXIT
    END DO
    DO iPart=1, PartNumChildNode(8)
      iPartIndx_ChildNode(iLoop2,PartNumChildNode(iLoop2)+iPart) = iPartIndx_ChildNode(8,iPart)
      MappedPart_ChildNode(iLoop2,PartNumChildNode(iLoop2)+iPart,1:3) = MappedPart_ChildNode(8,iPart,1:3)
      vBulk(1:3,iLoop2) = vBulk(1:3,iLoop2) + PartState(iPartIndx_ChildNode(8,iPart),4:6)
    END DO
    PartNumChildNode(iLoop2) = PartNumChildNode(iLoop2) + PartNumChildNode(8)
    PartNumChildNode(8) = 0
    NodeVolumeTemp(iLoop2) = NodeVolumeTemp(iLoop2) + NodeVolumeTemp(8)
    NodeVolumeTemp(8) = 0.0
  END IF
END IF


DO iLoop = 1, 8
  ! Octree can only performed if nPart is greater than the defined value (default=20), otherwise nearest neighbour pairing
  IF ((PartNumChildNode(iLoop).GE.(2.*BGKMinPartPerCell)).AND.(.NOT.ForceESBGK)) THEN
    ! Determination of the particle number per species for the calculation of the reference diameter for the mixture
    NULLIFY(TreeNode%ChildNode)
    ALLOCATE(TreeNode%ChildNode)
    ALLOCATE(TreeNode%ChildNode%iPartIndx_Node(PartNumChildNode(iLoop)))
    ALLOCATE(TreeNode%ChildNode%MappedPartStates(PartNumChildNode(iLoop),1:3))
    TreeNode%ChildNode%iPartIndx_Node(1:PartNumChildNode(iLoop)) = iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop))
    TreeNode%ChildNode%PNum_Node = PartNumChildNode(iLoop)
    TreeNode%ChildNode%MappedPartStates(1:PartNumChildNode(iLoop),1:3)= &
          MappedPart_ChildNode(iLoop,1:PartNumChildNode(iLoop),1:3)
    IF (iLoop.LT.5) THEN
      TreeNode%ChildNode%MidPoint(1) = 1.0
      IF (iLoop.LT.3) THEN
        TreeNode%ChildNode%MidPoint(2) = 1.0
      ELSE
        TreeNode%ChildNode%MidPoint(2) = -1.0
      END IF
    ELSE
      TreeNode%ChildNode%MidPoint(1) = -1.0
      IF (iLoop.LT.7) THEN
        TreeNode%ChildNode%MidPoint(2) = 1.0
      ELSE
        TreeNode%ChildNode%MidPoint(2) = -1.0
      END IF
    END IF
    IF ((iLoop.EQ.1).OR.(iLoop.EQ.4).OR.(iLoop.EQ.5).OR.(iLoop.EQ.8)) THEN
      TreeNode%ChildNode%MidPoint(3) = -1.0
    ELSE
      TreeNode%ChildNode%MidPoint(3) = 1.0
    END IF
    TreeNode%ChildNode%MidPoint(1:3) = TreeNode%MidPoint(1:3) &
                                     + TreeNode%ChildNode%MidPoint(1:3)*2.0/(2.0**(TreeNode%NodeDepth+1.0))
    TreeNode%ChildNode%NodeDepth = TreeNode%NodeDepth + 1
    ! Determination of the sub node number for the correct pointer handover (pointer acts as root for further octree division)
    IF (BGKDoAveraging) THEN
      IF (iLoop.EQ.1) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode1, Averaging%SubNode1)
      IF (iLoop.EQ.2) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode2, Averaging%SubNode2)
      IF (iLoop.EQ.3) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode3, Averaging%SubNode3)
      IF (iLoop.EQ.4) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode4, Averaging%SubNode4)
      IF (iLoop.EQ.5) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode5, Averaging%SubNode5)
      IF (iLoop.EQ.6) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode6, Averaging%SubNode6)
      IF (iLoop.EQ.7) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode7, Averaging%SubNode7)
      IF (iLoop.EQ.8) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode8, Averaging%SubNode8)
    ELSE
      IF (iLoop.EQ.1) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode1)
      IF (iLoop.EQ.2) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode2)
      IF (iLoop.EQ.3) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode3)
      IF (iLoop.EQ.4) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode4)
      IF (iLoop.EQ.5) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode5)
      IF (iLoop.EQ.6) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode6)
      IF (iLoop.EQ.7) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode7)
      IF (iLoop.EQ.8) CALL AddESBGKOctreeNode(TreeNode%ChildNode, iElem, NodeVol%SubNode8)
    END IF
    DEALLOCATE(TreeNode%ChildNode%MappedPartStates)
    DEALLOCATE(TreeNode%ChildNode%iPartIndx_Node)
    DEALLOCATE(TreeNode%ChildNode)
  ELSE IF (PartNumChildNode(iLoop).GE.2) THEN
    vBulk(1:3,iLoop) = vBulk(1:3,iLoop) / PartNumChildNode(iLoop)
    IF (BGKDoAveraging) THEN
      SELECT CASE(iLoop)
        CASE(1)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode1%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode1%CorrectStep)
        CASE(2)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode2%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode2%CorrectStep)
        CASE(3)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode3%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode3%CorrectStep)
        CASE(4)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode4%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode4%CorrectStep)
        CASE(5)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode5%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode5%CorrectStep)
        CASE(6)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode6%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode6%CorrectStep)
        CASE(7)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode7%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode7%CorrectStep)
        CASE(8)
          CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
                PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop), &
                Averaging%SubNode8%AverageValues(1:5,1:BGKAveragingLength), &
                CorrectStep = Averaging%SubNode8%CorrectStep)
      END SELECT
    ELSE
      CALL ESBGK_CollisionOperatorOctree(iPartIndx_ChildNode(iLoop, 1:PartNumChildNode(iLoop)), &
              PartNumChildNode(iLoop), iElem, NodeVolumeTemp(iLoop), vBulk(1:3,iLoop))
    END IF
  END IF
END DO

END SUBROUTINE AddESBGKOctreeNode


SUBROUTINE ESBGKSplitCells(iElem)
!===================================================================================================================================
!> description
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Vars      ,ONLY: PartState, PEM
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_ESBGK_CollOperator ,ONLY: ESBGK_CollisionOperatorOctree
USE MOD_ESBGK_Vars         ,ONLY: BGKMinPartPerCell, ElemSplitCells
USE MOD_Eval_xyz               ,ONLY: Eval_XYZ_ElemCheck
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)          :: iElem
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                      :: iPart, iLoop
INTEGER, ALLOCATABLE         :: iPartIndx_SplitCell(:,:,:,:), PartNum_SplitCell(:,:,:),  iPartIndx(:)
REAL, ALLOCATABLE            :: vBulk_SplitCell(:,:,:,:), MappedPartStates(:,:)
INTEGER                      :: PosX, PosY, PosZ, nPart
REAL                         :: vBulk(3)
!===================================================================================================================================
nPart = PEM%pNumber(iElem)
IF ((nPart.EQ.0).OR.(nPart.EQ.1)) THEN
  RETURN
END IF
IF(nPart.GE.(2.*BGKMinPartPerCell)) THEN
  ALLOCATE(iPartIndx_SplitCell(nPart, ElemSplitCells(iElem)%Splitnum(1)+1,  ElemSplitCells(iElem)%Splitnum(2)+1, &
        ElemSplitCells(iElem)%Splitnum(3)+1))
  ALLOCATE(vBulk_SplitCell(3, ElemSplitCells(iElem)%Splitnum(1)+1,  ElemSplitCells(iElem)%Splitnum(2)+1, &
        ElemSplitCells(iElem)%Splitnum(3)+1))
  ALLOCATE(PartNum_SplitCell(ElemSplitCells(iElem)%Splitnum(1)+1, ElemSplitCells(iElem)%Splitnum(2)+1, &
        ElemSplitCells(iElem)%Splitnum(3)+1))
  ALLOCATE(MappedPartStates(nPart, 1:3))
  iPartIndx_SplitCell = 0
  PartNum_SplitCell = 0
  vBulk_SplitCell= 0.0

  CALL CalcSplitCellVolumes(iElem)

  iPart = PEM%pStart(iElem)                         ! create particle index list for pairing
  DO iLoop = 1, nPart
    CALL Eval_XYZ_ElemCheck(PartState(iPart,1:3),MappedPartStates(iLoop,1:3),iElem)
!    CALL GeoCoordToMap(PartState(iPart,1:3), MappedPartStates(iLoop,1:3), iElem)
    PosX = INT((MappedPartStates(iLoop,1)+1.0)/2.0*(ElemSplitCells(iElem)%Splitnum(1)+1.)) + 1
    PosY = INT((MappedPartStates(iLoop,2)+1.0)/2.0*(ElemSplitCells(iElem)%Splitnum(2)+1.)) + 1
    PosZ = INT((MappedPartStates(iLoop,3)+1.0)/2.0*(ElemSplitCells(iElem)%Splitnum(3)+1.)) + 1
    PartNum_SplitCell(PosX, PosY, PosZ) = PartNum_SplitCell(PosX, PosY, PosZ) + 1
    iPartIndx_SplitCell(PartNum_SplitCell(PosX, PosY, PosZ), PosX, PosY, PosZ) = iPart
    vBulk_SplitCell(1:3, PosX, PosY, PosZ)  =  vBulk_SplitCell(1:3, PosX, PosY, PosZ) + PartState(iPart,4:6)
    iPart = PEM%pNext(iPart)
  END DO

  DO PosX = 1, ElemSplitCells(iElem)%Splitnum(1)+1; DO PosY = 1, ElemSplitCells(iElem)%Splitnum(2)+1
   DO PosZ = 1, ElemSplitCells(iElem)%Splitnum(3)+1
    IF (PartNum_SplitCell(PosX, PosY, PosZ).GE.2) THEN
        vBulk_SplitCell(1:3,PosX, PosY, PosZ) = vBulk_SplitCell(1:3,PosX, PosY, PosZ) /PartNum_SplitCell(PosX, PosY, PosZ)
        CALL ESBGK_CollisionOperatorOctree(iPartIndx_SplitCell(1:PartNum_SplitCell(PosX, PosY, PosZ),PosX, PosY, PosZ), &
                PartNum_SplitCell(PosX, PosY, PosZ), iElem, ElemSplitCells(iElem)%SplitCellVolumes(PosX, PosY, PosZ), &
                vBulk_SplitCell(1:3,PosX, PosY, PosZ))
    END IF
  END DO; END DO; END DO
ELSE
  ALLOCATE(iPartIndx(nPart))
  vBulk = 0.0
  iPart = PEM%pStart(iElem)                         ! create particle index list for pairing
  DO iLoop = 1, nPart
    iPartIndx(iLoop) = iPart
    vBulk(1:3)  =  vBulk(1:3) + PartState(iPart,4:6)
    iPart = PEM%pNext(iPart)
  END DO
  vBulk(1:3) = vBulk(1:3) / nPart
  CALL ESBGK_CollisionOperatorOctree(iPartIndx(1:nPart), nPart, iElem, GEO%Volume(iElem), vBulk(1:3))
END IF

END SUBROUTINE ESBGKSplitCells

integer function lcm(a,b)
integer:: a,b
    lcm = a*b / gcd(a,b)
end function lcm

integer function gcd(a,b)
integer :: a,b,t
    do while (b/=0)
        t = b
        b = mod(a,b)
        a = t
    end do
    gcd = abs(a)
end function gcd


SUBROUTINE CalcSplitCellVolumes(iElem)
!===================================================================================================================================
!> description
!===================================================================================================================================
! MODULES
USE MOD_Mesh_Vars          ,ONLY: sJ
USE MOD_PreProc            ,ONLY: PP_N
USE MOD_ChangeBasis        ,ONLY: ChangeBasis3D
USE MOD_PreProc            ,ONLY: PP_N
USE MOD_ESBGK_Vars         ,ONLY: ElemSplitCells
USE MOD_Interpolation_Vars ,ONLY: xGP, wBary
USE MOD_Basis              ,ONLY: InitializeVandermonde
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)                     :: iElem
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                                 :: j, k ,l, NumOfPoints
REAL                                    :: DetLocal(1,0:PP_N,0:PP_N,0:PP_N), LocalwGP
REAL, ALLOCATABLE                       :: DetJac(:,:,:,:)
REAL, ALLOCATABLE                       :: LocalVdm(:,:), LocalxGP(:)
INTEGER                                 :: LocalDepth, LowestCommonMultipl, PosX, PosY, PosZ
!===================================================================================================================================
IF (ALLOCATED(ElemSplitCells(iElem)%SplitCellVolumes)) THEN
  IF (((ElemSplitCells(iElem)%Splitnum(1)+1).EQ.SIZE(ElemSplitCells(iElem)%SplitCellVolumes,1)) &
     .AND.((ElemSplitCells(iElem)%Splitnum(2)+1).EQ.SIZE(ElemSplitCells(iElem)%SplitCellVolumes,2)) &
     .AND.((ElemSplitCells(iElem)%Splitnum(3)+1).EQ.SIZE(ElemSplitCells(iElem)%SplitCellVolumes,3))) RETURN

  DEALLOCATE(ElemSplitCells(iElem)%SplitCellVolumes)
END IF
ALLOCATE(ElemSplitCells(iElem)%SplitCellVolumes(ElemSplitCells(iElem)%Splitnum(1)+1, ElemSplitCells(iElem)%Splitnum(2)+1, &
  ElemSplitCells(iElem)%Splitnum(3)+1))
DO j=0, PP_N; DO k=0, PP_N; DO l=0, PP_N
  DetLocal(1,j,k,l)=1./sJ(j,k,l,iElem)
END DO; END DO; END DO
LowestCommonMultipl = lcm(ElemSplitCells(iElem)%Splitnum(1)+1, ElemSplitCells(iElem)%Splitnum(2)+1)
LowestCommonMultipl = lcm(LowestCommonMultipl, ElemSplitCells(iElem)%Splitnum(3)+1)

ALLOCATE( DetJac(1,0:LowestCommonMultipl - 1,0:LowestCommonMultipl - 1,0:LowestCommonMultipl - 1))
ALLOCATE(LocalVdm(0:LowestCommonMultipl - 1,0:PP_N))
ALLOCATE(LocalxGP(0:LowestCommonMultipl - 1))
DO j=0,LowestCommonMultipl - 1
  LocalxGP(j) = -1.0 + 2./LowestCommonMultipl * (REAL(j)+ 0.5) 
END DO
LocalwGP = 2./REAL(LowestCommonMultipl)
CALL InitializeVandermonde(PP_N,LowestCommonMultipl - 1,wBary,xGP,LocalxGP,LocalVdm)

CALL ChangeBasis3D(1,PP_N, LowestCommonMultipl - 1, LocalVdm, DetLocal(:,:,:,:),DetJac(:,:,:,:))

ElemSplitCells(iElem)%SplitCellVolumes = 0.0
DO j = 0 ,LowestCommonMultipl-1;   DO k = 0 ,LowestCommonMultipl-1;   DO l = 0 ,LowestCommonMultipl-1
  PosX = INT(j/(LowestCommonMultipl/(ElemSplitCells(iElem)%Splitnum(1)+1))) + 1
  PosY = INT(k/(LowestCommonMultipl/(ElemSplitCells(iElem)%Splitnum(2)+1))) + 1
  PosZ = INT(l/(LowestCommonMultipl/(ElemSplitCells(iElem)%Splitnum(3)+1))) + 1
  ElemSplitCells(iElem)%SplitCellVolumes(PosX, PosY, PosZ) = ElemSplitCells(iElem)%SplitCellVolumes(PosX, PosY, PosZ) &
    +  DetJac(1, j ,k, l) * LocalwGP**3.0
END DO; END DO; END DO

END SUBROUTINE CalcSplitCellVolumes

SUBROUTINE BGK_AllocateAveragingNode(Averaging)
!===================================================================================================================================
! description
!===================================================================================================================================
! MODULES
USE MOD_ESBGK_Vars,             ONLY :tNodeAverage, BGKAveragingLength
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
TYPE(tNodeAverage),INTENT(INOUT), POINTER, OPTIONAL :: Averaging
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
ALLOCATE(Averaging%SubNode1)
ALLOCATE(Averaging%SubNode2)
ALLOCATE(Averaging%SubNode3)
ALLOCATE(Averaging%SubNode4)
ALLOCATE(Averaging%SubNode5)
ALLOCATE(Averaging%SubNode6)
ALLOCATE(Averaging%SubNode7)
ALLOCATE(Averaging%SubNode8)

ALLOCATE(Averaging%SubNode1%AverageValues(5,BGKAveragingLength))
ALLOCATE(Averaging%SubNode2%AverageValues(5,BGKAveragingLength))
ALLOCATE(Averaging%SubNode3%AverageValues(5,BGKAveragingLength))
ALLOCATE(Averaging%SubNode4%AverageValues(5,BGKAveragingLength))
ALLOCATE(Averaging%SubNode5%AverageValues(5,BGKAveragingLength))
ALLOCATE(Averaging%SubNode6%AverageValues(5,BGKAveragingLength))
ALLOCATE(Averaging%SubNode7%AverageValues(5,BGKAveragingLength))
ALLOCATE(Averaging%SubNode8%AverageValues(5,BGKAveragingLength))

Averaging%SubNode1%AverageValues = 0.0
Averaging%SubNode2%AverageValues = 0.0
Averaging%SubNode3%AverageValues = 0.0
Averaging%SubNode4%AverageValues = 0.0
Averaging%SubNode5%AverageValues = 0.0
Averaging%SubNode6%AverageValues = 0.0
Averaging%SubNode7%AverageValues = 0.0
Averaging%SubNode8%AverageValues = 0.0

Averaging%SubNode1%CorrectStep = 0
Averaging%SubNode2%CorrectStep = 0
Averaging%SubNode3%CorrectStep = 0
Averaging%SubNode4%CorrectStep = 0
Averaging%SubNode5%CorrectStep = 0
Averaging%SubNode6%CorrectStep = 0
Averaging%SubNode7%CorrectStep = 0
Averaging%SubNode8%CorrectStep = 0

END SUBROUTINE BGK_AllocateAveragingNode

END MODULE MOD_ESBGK_Adaptation
