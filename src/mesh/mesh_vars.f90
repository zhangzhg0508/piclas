#include "boltzplatz.h"

MODULE MOD_Mesh_Vars
!===================================================================================================================================
!> Contains global variables provided by the mesh routines
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
LOGICAL          :: DoWriteStateToHDF5           !< only write HDF5 output if this is true
!-----------------------------------------------------------------------------------------------------------------------------------
! SwapMesh
!-----------------------------------------------------------------------------------------------------------------------------------
LOGICAL           :: DoSwapMesh                   !< flag for SwapMesh routines
CHARACTER(LEN=255):: SwapMeshExePath              !< path to swapmesh binary
INTEGER           :: SwapMeshLevel                !< 0: initial grid, 1: first swap mesh, 2: second swap mesh
!-----------------------------------------------------------------------------------------------------------------------------------
! basis
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER          :: NGeo                        !< polynomial degree of geometric transformation
INTEGER          :: NGeoRef                     !< polynomial degree of geometric transformation
INTEGER          :: NGeoElevated                !< polynomial degree of elevated geometric transformation
REAL,ALLOCATABLE :: Xi_NGeo(:)                  !< 1D equidistant point positions for curved elements (during readin)
REAL             :: DeltaXi_NGeo
! check if these arrays are still used
REAL,ALLOCATABLE :: Vdm_CLN_GaussN(:,:)
REAL,ALLOCATABLE :: Vdm_CLNGeo_CLN(:,:)
REAL,ALLOCATABLE :: Vdm_CLNGeo_GaussN(:,:)  
REAL,ALLOCATABLE :: Vdm_NGeo_CLNGeo(:,:)  
REAL,ALLOCATABLE :: DCL_NGeo(:,:)  
REAL,ALLOCATABLE :: DCL_N(:,:)  
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! will be used in the future
REAL,ALLOCATABLE,TARGET :: NodeCoords(:,:,:,:,:) !< XYZ positions (equidistant,NGeo) of element interpolation points from meshfile
REAL,ALLOCATABLE :: Elem_xGP(:,:,:,:,:)   !< XYZ positions (first index 1:3) of the volume Gauss Point
REAL,ALLOCATABLE :: Face_xGP(:,:,:,:)   !< XYZ positions (first index 1:3) of the Boundary Face Gauss Point
!----------------------------------------------------------------------------------------------------------------------------------
! MORTAR DATA FOR NON-CONFORMING MESHES ORIGINATING FROM AN OCTREE BASIS (ONLY ALLOCATED IF isMortarMesh=.TRUE.!!!)
!----------------------------------------------------------------------------------------------------------------------------------
LOGICAL          :: isMortarMesh               !< Marker whether non-conforming data is present (false for conforming meshes)
LOGICAL          :: interpolateFromTree        !< Switch whether to build metrics on tree level and interpolate to elements.
                                               !< Only applicable if tree data is present in mesh file
REAL,ALLOCATABLE,TARGET :: TreeCoords(:,:,:,:,:) !< XYZ positions (equidistant,NGeoTree) of tree interpolation points from meshfile
REAL,ALLOCATABLE :: xiMinMax(:,:,:)            !< Position of the 2 bounding nodes of a quadrant in its tree
INTEGER          :: NGeoTree                   !< Polynomial degree of trees geometric transformation
INTEGER          :: nTrees                     !< Local number of trees in mesh
INTEGER          :: nGlobalTrees               !< Global number of trees in mesh
INTEGER          :: offsetTree                 !< Tree offset (for MPI)
INTEGER,ALLOCATABLE :: ElemToTree(:)           !< Index of the tree corresponding to an element
!-----------------------------------------------------------------------------------------------------------------------------------
! Metrics on GaussPoints 
!-----------------------------------------------------------------------------------------------------------------------------------
REAL,ALLOCATABLE :: Metrics_fTilde(:,:,:,:,:) !< Metric Terms (first indices 3) on each GaussPoint
REAL,ALLOCATABLE :: Metrics_gTilde(:,:,:,:,:)
REAL,ALLOCATABLE :: Metrics_hTilde(:,:,:,:,:)
REAL,ALLOCATABLE :: sJ(:,:,:,:)               !< 1/DetJac for each Gauss Point
!-----------------------------------------------------------------------------------------------------------------------------------
! PIC - for Newton localisation of particles in curved Elements
!-----------------------------------------------------------------------------------------------------------------------------------
REAL,ALLOCATABLE    :: wBaryCL_NGeo(:)
!< #ifdef PARTICLES
REAL,ALLOCATABLE    :: wBaryCL_NGeo1(:)
REAL,ALLOCATABLE    :: XiCL_NGeo1(:)
REAL,ALLOCATABLE    :: Vdm_CLNGeo1_CLNGeo(:,:)
LOGICAL,ALLOCATABLE :: CurvedElem(:)
!< #endif /*PARTICLES*/
REAL,ALLOCATABLE    :: XiCL_NGeo(:)
REAL,ALLOCATABLE    :: XCL_NGeo(:,:,:,:,:)
REAL,ALLOCATABLE    :: dXCL_NGeo(:,:,:,:,:,:) !jacobi matrix of the mapping P\in NGeo
REAL,ALLOCATABLE    :: dXCL_N(:,:,:,:,:,:) !jacobi matrix of the mapping P\in NGeo
REAL,ALLOCATABLE    :: detJac_Ref(:,:,:,:,:)      !< determinant of the mesh Jacobian for each Gauss point at degree 3*NGeo
!-----------------------------------------------------------------------------------------------------------------------------------
! surface vectors 
!-----------------------------------------------------------------------------------------------------------------------------------
REAL,ALLOCATABLE :: NormVec(:,:,:,:)           !< normal vector for each side       (1:3,0:N,0:N,nSides)
REAL,ALLOCATABLE :: TangVec1(:,:,:,:)          !< tangential vector 1 for each side (1:3,0:N,0:N,nSides)
REAL,ALLOCATABLE :: TangVec2(:,:,:,:)          !< tangential vector 3 for each side (1:3,0:N,0:N,nSides)
REAL,ALLOCATABLE :: SurfElem(:,:,:)            !< surface area for each side        (    0:N,0:N,nSides)
REAL,ALLOCATABLE :: Ja_Face(:,:,:,:)           !< surface  metrics for each side
!-----------------------------------------------------------------------------------------------------------------------------------
! mapping from GaussPoints to Side or Neighbor Volume
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER,ALLOCATABLE :: VolToSideA(:,:,:,:,:,:)
INTEGER,ALLOCATABLE :: VolToSideIJKA(:,:,:,:,:,:)
INTEGER,ALLOCATABLE :: VolToSide2A(:,:,:,:,:)
INTEGER,ALLOCATABLE :: CGNS_VolToSideA(:,:,:,:,:)
INTEGER,ALLOCATABLE :: CGNS_SideToVol2A(:,:,:,:)
INTEGER,ALLOCATABLE :: SideToVolA(:,:,:,:,:,:)
INTEGER,ALLOCATABLE :: SideToVol2A(:,:,:,:,:)
INTEGER,ALLOCATABLE :: FS2M(:,:,:,:)     !< flip slave side to master and reverse
!-----------------------------------------------------------------------------------------------------------------------------------
! mapping from element to sides and sides to element
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER,ALLOCATABLE :: ElemToSide(:,:,:) !< SideID    = ElemToSide(E2S_SIDE_ID,ZETA_PLUS,iElem)
                                         !< flip      = ElemToSide(E2S_FLIP,ZETA_PLUS,iElem)
INTEGER,ALLOCATABLE :: SideToElem(:,:)   !< ElemID    = SideToElem(S2E_ELEM_ID,SideID)
                                         !< NB_ElemID = SideToElem(S2E_NB_ELEM_ID,SideID)
                                         !< locSideID = SideToElem(S2E_LOC_SIDE_ID,SideID)
INTEGER,ALLOCATABLE :: BC(:)             !< BCIndex   = BC(SideID), 1:nCSides
INTEGER,ALLOCATABLE :: BoundaryType(:,:) !< BCType    = BoundaryType(BC(SideID),BC_TYPE)
                                         !< BCState   = BoundaryType(BC(SideID),BC_STATE)
INTEGER,ALLOCATABLE :: AnalyzeSide(:)    !< Marks, wheter a side belongs to a group of analyze sides (e.g. to a BC group)
                                         !< SurfIndex = AnalyzeSide(SideID), 1:nSides

INTEGER,PARAMETER :: NormalDirs(6) = (/ 3 , 2 , 1 , 2 , 1 , 3 /) !< normal vector direction for element local side
INTEGER,PARAMETER :: TangDirs(6)   = (/ 1 , 3 , 2 , 3 , 2 , 1 /) !< first tangential vector direction for element local side
REAL   ,PARAMETER :: NormalSigns(6)= (/-1.,-1., 1., 1.,-1., 1./) !< normal vector sign for element local side

!----------------------------------------------------------------------------------------------------------------------------------
! Volume/Side mappings filled by mappings.f90 - not all available there are currently used!
!----------------------------------------------------------------------------------------------------------------------------------
!INTEGER,ALLOCATABLE :: V2S(:,:,:,:,:,:)  !< volume to side mapping
!INTEGER,ALLOCATABLE :: V2S2(:,:,:,:,:)   !< volume to side mapping 2
!INTEGER,ALLOCATABLE :: S2V(:,:,:,:,:,:)  !< side to volume
!INTEGER,ALLOCATABLE :: S2V2(:,:,:,:,:)   !< side to volume 2
!INTEGER,ALLOCATABLE :: S2V3(:,:,:,:,:)   !< side to volume 3
!INTEGER,ALLOCATABLE :: CS2V2(:,:,:,:)    !< CGNS side to volume 2
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER          :: nGlobalElems=0      !< number of elements in mesh
INTEGER          :: nElems=0            !< number of local elements
INTEGER          :: offsetElem=0        !< for MPI, until now=0 Elems pointer array range: [offsetElem+1:offsetElem+nElems]
INTEGER          :: nSides=0            !< =nInnerSides+nBCSides+nMPISides
INTEGER          :: nUniqueSides=0 !< =uniquesides for hdg output
INTEGER          :: offsetSide=0        !< for MPI, until now=0  Sides pointer array range
INTEGER          :: nSidesMaster=0          !< =sideIDMaster
INTEGER          :: nSidesSlave=0           !< =nInnerSides+nBCSides+nMPISides
INTEGER          :: nInnerSides=0           !< InnerSide index range: sideID [nBCSides+1:nBCSides+nInnerSides]
INTEGER          :: nBCSides=0              !< BCSide index range: sideID [1:nBCSides]
INTEGER          :: nAnalyzeSides=0         !< marker for each side (BC,analyze flag, periodic,...)
INTEGER          :: nMPISides=0             !< number of MPI sides in mesh
INTEGER          :: nMPISides_MINE=0        !< number of MINE MPI sides (on local processor)
INTEGER          :: nMPISides_YOUR=0        !< number of YOUR MPI sides (on neighbour processors)
INTEGER          :: nBCs=0                  !< number of BCs in mesh
INTEGER          :: nUserBCs=0              !< number of BC in inifile
!----------------------------------------------------------------------------------------------------------------------------------
! Define index ranges for all sides in consecutive order for easier access
INTEGER             :: firstBCSide             !< First SideID of BCs (in general 1)
INTEGER             :: firstMortarInnerSide    !< First SideID of Mortars (in general nBCs+1)
INTEGER             :: firstInnerSide          !< First SideID of inner sides
INTEGER             :: firstMPISide_MINE       !< First SideID of MINE MPI sides (on local processor)
INTEGER             :: firstMPISide_YOUR       !< First SideID of YOUR MPI sides (on neighbour processor)
INTEGER             :: firstMortarMPISide      !< First SideID of Mortar MPI sides
INTEGER             :: lastBCSide              !< Last  SideID of BCs (in general nBCs)
INTEGER             :: lastMortarInnerSide     !< Last  SideID of Mortars (in general nBCs+nMortars)
INTEGER             :: lastInnerSide           !< Last  SideID of inner sides
INTEGER             :: lastMPISide_MINE        !< Last  SideID of MINE MPI sides (on local processor)
INTEGER             :: lastMPISide_YOUR        !< Last  SideID of YOUR MPI sides (on neighbour processor)
INTEGER             :: lastMortarMPISide       !< Last  SideID of Mortar MPI sides (in general nSides)
!----------------------------------------------------------------------------------------------------------------------------------
INTEGER             :: nMortarSides=0          !< total number of mortar sides
INTEGER             :: nMortarInnerSides=0     !< number of inner mortar sides
INTEGER             :: nMortarMPISides=0       !< number of mortar MPI sides
INTEGER,ALLOCATABLE :: MortarType(:,:)         !< Type of mortar [1] and position in mortar list [1:nSides]
INTEGER,ALLOCATABLE :: MortarInfo(:,:,:)       !< 1:2,1:4,1:nMortarSides: [1] nbSideID / flip, [2] max 4 mortar sides, [3] sides
!-----------------------------------------------------------------------------------------------------------------------------------
CHARACTER(LEN=255),ALLOCATABLE   :: BoundaryName(:)
CHARACTER(LEN=255)               :: MeshFile        !< name of hdf5 meshfile (write with ending .h5!)
!-----------------------------------------------------------------------------------------------------------------------------------
LOGICAL          :: useCurveds
LOGICAL          :: CrossProductMetrics=.FALSE.
!-----------------------------------------------------------------------------------------------------------------------------------
!< PoyntingVectorIntegral variables
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER             :: nPoyntingIntSides=0   !< Sides for the calculation of the poynting vector
LOGICAL,ALLOCATABLE :: isPoyntingIntSide(:)  !< number of all PoyntingInt sides
INTEGER,ALLOCATABLE :: whichPoyntingPlane(:) !< number of plane used for calculation of poynting vector
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! USER DEFINED TYPES 

TYPE tNodePtr
  TYPE(tNode),POINTER          :: np                     !< node pointer
END TYPE tNodePtr

TYPE tSidePtr
  TYPE(tSide),POINTER          :: sp                     !< side pointer
END TYPE tSidePtr

TYPE tElemPtr
  TYPE(tElem),POINTER          :: ep                     !< Local element pointer
END TYPE tElemPtr

TYPE tElem
  INTEGER                      :: ind             !< global element index
  INTEGER                      :: Type            !< element type (linear/bilinear/curved)
  INTEGER                      :: Zone
  TYPE(tSidePtr),POINTER       :: Side(:)
END TYPE tElem

TYPE tSide
  INTEGER                      :: ind             !< global side ID 
  INTEGER                      :: sideID          !< local side ID on Proc 
  INTEGER                      :: tmp 
  INTEGER                      :: NbProc 
  INTEGER                      :: BCindex         !< index in BoundaryType array! 
  INTEGER                      :: flip 
  INTEGER                      :: nMortars        !< number of slave mortar sides associated with master mortar
  INTEGER                      :: MortarType      !< type of mortar: Type1 : 1-4 , Type 2: 1-2 in eta, Type 2: 1-2 in xi
  TYPE(tSidePtr),POINTER       :: MortarSide(:)   !< array of side pointers to slave mortar sides
  TYPE(tElem),POINTER          :: Elem
  TYPE(tSide),POINTER          :: connection
END TYPE tSide

TYPE tNode
  INTEGER                      :: ind=0         !< global unique node index
  REAL                         :: x(3)=0.
END TYPE tNode
!-----------------------------------------------------------------------------------------------------------------------------------
TYPE(tElemPtr),POINTER         :: Elems(:)
!-----------------------------------------------------------------------------------------------------------------------------------
LOGICAL          :: MeshInitIsDone =.FALSE.
!===================================================================================================================================

INTERFACE getNewSide
  MODULE PROCEDURE getNewSide
END INTERFACE

INTERFACE getNewElem
  MODULE PROCEDURE getNewElem
END INTERFACE

INTERFACE deleteMeshPointer
  MODULE PROCEDURE deleteMeshPointer
END INTERFACE

CONTAINS

FUNCTION GETNEWSIDE()
!===================================================================================================================================
!<  
!===================================================================================================================================
!< MODULES
!< IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!< INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
!< OUTPUT VARIABLES
TYPE(tSide),POINTER :: getNewSide
!-----------------------------------------------------------------------------------------------------------------------------------
!< LOCAL VARIABLES
!===================================================================================================================================
ALLOCATE(getNewSide)
NULLIFY(getNewSide%Elem)
NULLIFY(getNewSide%MortarSide)
NULLIFY(getNewSide%connection)
getNewSide%sideID=0
getNewSide%ind=0
getNewSide%tmp=0
getNewSide%NbProc=-1
getNewSide%BCindex=0
getNewSide%flip=0
getNewSide%nMortars=0
getNewSide%MortarType=0
END FUNCTION GETNEWSIDE

FUNCTION GETNEWELEM()
!===================================================================================================================================
!< 
!===================================================================================================================================
!< MODULES
!< IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!< INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
!< OUTPUT VARIABLES
TYPE(tElem),POINTER :: getNewElem
!-----------------------------------------------------------------------------------------------------------------------------------
!< LOCAL VARIABLES
INTEGER             :: iLocSide
!===================================================================================================================================
ALLOCATE(getNewElem)
ALLOCATE(getNewElem%Side(6))
DO iLocSide=1,6
  getNewElem%Side(iLocSide)%sp=>getNewSide()
END DO
getNewElem%ind=0
getNewElem%Zone=0
getNewElem%Type=0
END FUNCTION GETNEWELEM



SUBROUTINE deleteMeshPointer()
!===================================================================================================================================
!> Deallocates all pointers used for the mesh readin
!===================================================================================================================================
!< MODULES
!< IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER       :: FirstElemInd,LastElemInd
INTEGER       :: iElem,iLocSide
INTEGER       :: iMortar
TYPE(tElem),POINTER :: aElem
TYPE(tSide),POINTER :: aSide
!===================================================================================================================================
FirstElemInd = offsetElem+1
LastElemInd  = offsetElem+nElems
DO iElem=FirstElemInd,LastElemInd
  aElem=>Elems(iElem)%ep
  DO iLocSide=1,6
    aSide=>aElem%Side(iLocSide)%sp
    DO iMortar=1,aSide%nMortars
      NULLIFY(aSide%MortarSide(iMortar)%sp)
    END DO
    DEALLOCATE(aSide)
  END DO
  DEALLOCATE(aElem%Side)
  DEALLOCATE(aElem)
END DO
DEALLOCATE(Elems)
END SUBROUTINE deleteMeshPointer


END MODULE MOD_Mesh_Vars
