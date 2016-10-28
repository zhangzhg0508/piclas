#include "boltzplatz.h"

MODULE MOD_Particle_Surfaces_Vars
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
REAL,ALLOCATABLE,DIMENSION(:,:,:)       :: BiLinearCoeff                ! contains the bi-linear coefficients for each side
REAL,ALLOCATABLE,DIMENSION(:,:,:,:)     :: BezierControlPoints3D        ! Bezier basis control points of degree equal to NGeo
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors0                 ! vectors for building intersectionsurfaces for particle
                                                                        ! from Bezierpoints (1:3,1:nBCSurfaces)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors1                 ! vectors for building intersectionsurfaces for particle
                                                                        ! from Bezierpoints (1:3,1:nBCSurfaces)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors2                 ! vectors for building intersectionsurfaces for particle
                                                                        ! from Bezierpoints (1:3,1:nBCSurfaces)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors3                 ! additional vector for bilinear intersection
                                                                        ! from Bezierpoints (1:3,1:nBCSurfaces)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors0flip             ! vectors for building intersectionsurfaces for particle
                                                                        ! from Bezierpoints for Periodic sites (1:3,1:nBCSurfaces)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors1flip             ! vectors for building intersectionsurfaces for particle
                                                                        ! from Bezierpoints for Periodic sites(1:3,1:nBCSurfaces)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors2flip             ! vectors for building intersectionsurfaces for particle
                                                                        ! from Bezierpoints for Periodic sites(1:3,1:nBCSurfaces)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: BaseVectors3flip             ! additional vector for bilinear intersection
                                                                        ! from Bezierpoints for Periodic sites(1:3,1:nBCSurfaces)
! INTEGER,ALLOCATABLE,DIMENSION(:)        :: SideID2PlanarSideID
REAL,ALLOCATABLE,DIMENSION(:,:,:,:)     :: BezierControlPoints3DElevated! Bezier basis control points of degree equal to NGeo
REAL,ALLOCATABLE,DIMENSION(:,:)         :: ElevationMatrix              ! array for binomial coefficients used for Bezier Elevation
REAL,ALLOCATABLE,DIMENSION(:,:,:)       :: SideSlabNormals              ! normal vectors of bounding slab box (Sides)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: SideSlabIntervals            ! intervalls beta1, beta2, beta3 (Sides)
REAL,ALLOCATABLE,DIMENSION(:,:,:)       :: ElemSlabNormals              ! normal vectors of bounding slab box (Elements)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: ElemSlabIntervals            ! intervalls beta1, beta2, beta3 (Elements)
REAL,ALLOCATABLE,DIMENSION(:,:)         :: Vdm_Bezier,sVdm_Bezier       ! Vdm from/to Bezier Polynomial from BC representation
REAL,ALLOCATABLE,DIMENSION(:,:)         :: D_Bezier                     ! D-Matrix of Bezier Polynomial from BC representation
REAL,ALLOCATABLE,DIMENSION(:,:)         :: arrayNchooseK                ! array for binomial coefficients
REAL,ALLOCATABLE,DIMENSION(:,:)         :: FacNchooseK                  ! array for binomial coefficients times prefactor
INTEGER,ALLOCATABLE,DIMENSION(:)        :: SideType                     ! integer array with side type - planar - bilinear - curved
LOGICAL,ALLOCATABLE,DIMENSION(:)        :: BoundingBoxIsEmpty           ! logical if Side bounding box is empty
REAL,ALLOCATABLE,DIMENSION(:,:)         :: SideNormVec                  ! normal Vector of planar sides
REAL,ALLOCATABLE,DIMENSION(:)           :: SideDistance                 ! distance of planar base from origin 
INTEGER,ALLOCATABLE,DIMENSION(:)        :: gElemBCSides                 ! number of BC-Sides of element
REAL                                    :: BezierEpsilonBilinear        ! bi-linear tolerance for the bi-linear - planar decision
REAL                                    :: BezierHitEpsBi               ! epsilon tolerance for bi-linear faces
REAL                                    :: epsilontol                   ! epsilon for setting the tolerance
REAL                                    :: OneMinusEps                  ! 1 - eps: epsilontol
REAL                                    :: OnePlusEps                   ! 1 + eps: epsilontol for setting the boundary tolerance
REAL                                    :: MinusEps                     ! - eps: epsilontol
LOGICAL                                 :: ParticleSurfaceInitIsDone=.FALSE.
! settings for Bezier-Clipping and definition of maximal number of intersections
REAL                                    :: BezierNewtonAngle            ! switch for intersection with bezier newton algorithm
                                                                        ! smallest angle of impact of particle trajectory on face
REAL                                    :: BezierClipHit                ! value for clip hit
REAL                                    :: BezierClipTolerance          ! tolerance for root of bezier clipping
REAL                                    :: BezierSplitLimit             ! clip if remaining area after clip is > clipforce %
INTEGER                                 :: BezierClipMaxIntersec        ! maximal possible intersections for Bezier clipping
INTEGER                                 :: BezierClipMaxIter            ! maximal iterations per intersections
INTEGER                                 :: BezierElevation              ! elevate polynomial degree to NGeo+BezierElevation
REAL,ALLOCATABLE,DIMENSION(:)           :: locAlpha,locXi,locEta        ! position of trajectory-patch
REAL,ALLOCATABLE,DIMENSION(:,:)         :: XiArray,EtaArray             ! xi and eta history for computation of intersection
!LOGICAL                                 :: MultipleBCs                  ! allow for multiple BC during one tracking step
                                                                        ! only for do-ref-mapping required
#ifdef CODE_ANALYZE
REAL                                    :: rBoundingBoxChecks           ! number of bounding box checks
REAL(KIND=16)                           :: rTotalBBChecks               ! total number of bounding box checks
REAL                                    :: rPerformBezierClip           ! number of performed bezier clips
REAL                                    :: rPerformBezierNewton         ! number of performed bezier newton intersections
REAL(KIND=16)                           :: rTotalBezierClips            ! total number of performed bezier clips
REAL(KIND=16)                           :: rTotalBezierNewton           ! total number of performed bezier newton intersections
REAL,ALLOCATABLE,DIMENSION(:)           :: SideBoundingBoxVolume        ! Bounding Box volume
#endif /*CODE_ANALYZE*/

! Surface sampling
INTEGER                                 :: BezierSampleN                ! equidistant sampling of bezier surface for emission
REAL,ALLOCATABLE,DIMENSION(:)           :: BezierSampleXi               ! ref coordinate for equidistant bezier surface sampling

REAL,ALLOCATABLE,DIMENSION(:)           :: SurfMeshSideAreas            ! areas of of sides of surface mesh (1:nBCSides)
TYPE tSurfMeshSubSideData
  REAL                                   :: vec_nIn(3)                  ! inward directed normal of sub-sides of surface mesh
  REAL                                   :: vec_t1(3)                   ! first orth. vector in sub-sides of surface mesh
  REAL                                   :: vec_t2(3)                   ! second orth. vector in sub-sides of surface mesh
  REAL                                   :: area                        ! area of sub-sides of surface mesh
END TYPE tSurfMeshSubSideData
TYPE(tSurfMeshSubSideData),ALLOCATABLE   :: SurfMeshSubSideData(:,:,:)  ! areas of of sub-sides of surface mesh
                                                                        ! (1:BezierSampleN,1:BezierSampleN,1:nBCSides)
TYPE tBCdata_auxSF
  INTEGER                                :: SideNumber                  ! Number of Particles in Sides in SurfacefluxBC
  INTEGER                , ALLOCATABLE   :: SideList(:)                 ! List of Sides in BC (1:SideNumber)
END TYPE tBCdata_auxSF
TYPE(tBCdata_auxSF),ALLOCATABLE          :: BCdata_auxSF(:)             !aux. data of BCs for surfacefluxes, (1:nPartBound) (!!!)


!===================================================================================================================================

END MODULE MOD_Particle_Surfaces_Vars
