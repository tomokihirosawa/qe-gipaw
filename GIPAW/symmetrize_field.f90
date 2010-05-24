!
! Copyright (C) 2008-2010 Quantum ESPRESSO and GIPAW group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!
!-----------------------------------------------------------------------
SUBROUTINE symmetrize_field(field, iflag)
  !-----------------------------------------------------------------------
  !
  !     symmetrize a tensor field (e.g. current or induced magnetic field)
  !     iflag = 0  => tensor         (e.g. induced B field)
  !     iflag = 1  => pseudo-tensor  (e.g. induced current)
  !
  !     don't use nrxxs: in the parallel case nrx1s*nrx2s*nrx3s /= nrxxs
  !
  USE kinds,                           ONLY : DP
  USE cell_base,                       ONLY : at, bg
  USE symm_base,                       ONLY : s, nsym
  USE symme,                           ONLY : crys_to_cart, cart_to_crys
  USE pwcom
  USE gipaw_module

  !-- parameters ------------------------------------------------------
  IMPLICIT NONE
  REAL(DP), INTENT(INOUT) :: field(nrx1s*nrx2s*nrx3s,3,3)
  INTEGER :: iflag

  !-- local variables ----------------------------------------------------
  complex(dp), allocatable :: aux(:)
  real(dp) :: tmp(3,3)
  integer :: i, ipol, jpol

  ! if no symmetries, return
  if (nsym <= 1) return

  ! cartesian to crystal
  do i = 1, nrx1s*nrx2s*nrx3s
    tmp(:,:) = field(i,:,:)
    call cart_to_crys ( tmp )
    field(i,:,:) = tmp(:,:)
  enddo
  
  ! symmetrize
  call syme2(field, iflag)

  ! crystal to cartesian
  do i = 1, nrx1s*nrx2s*nrx3s
    tmp(:,:) = field(i,:,:)
    call crys_to_cart ( tmp )
    field(i,:,:) = tmp(:,:)
  enddo

END SUBROUTINE symmetrize_field


!-----------------------------------------------------------------------
SUBROUTINE psymmetrize_field(field, iflag)
  !-----------------------------------------------------------------------
  !
  !     symmetrize a tensor field (e.g. current or induced magnetic field)
  !     (parallel version)
  !     iflag = 0  => tensor         (e.g. induced B field)
  !     iflag = 1  => pseudo-tensor  (e.g. induced current)
  !
  USE kinds,                           ONLY : DP
  USE fft_base,                        ONLY : gather_smooth, scatter_smooth
  USE mp_global,                       ONLY : me_pool
  USE symm_base,                       ONLY : s, nsym
  USE pwcom
  USE gipaw_module

  !-- parameters ------------------------------------------------------
  IMPLICIT NONE
  REAL(DP), INTENT(INOUT) :: field(nrxxs,3,3)
  INTEGER :: iflag

  !-- local variables ----------------------------------------------------
  real(dp), allocatable :: aux(:,:,:)
  integer :: i, j

  ! if no symmetries, return
  if (nsym.eq.1) return

  allocate( aux(nrx1s*nrx2s*nrx3s,3,3) )
  do i = 1, 3
    do j = 1, 3
      call gather_smooth(field(:,i,j), aux(:,i,j))
    enddo
  enddo

  if ( me_pool == 0 ) call symmetrize_field(aux, iflag)

  do i = 1, 3
    do j = 1, 3
      call scatter_smooth(aux(:,i,j), field(:,i,j))
    enddo
  enddo

  deallocate(aux)
END SUBROUTINE psymmetrize_field

!---------------------------------------------------------------------
subroutine syme2 (dvsym, iflag)
  !-------------------------------------------------------------------
  use kinds,          ONLY : dp
  USE symm_base,      ONLY : s, nsym, ftau
  USE symme,          ONLY : crys_to_cart
  use pwcom
  implicit none

  real(DP) :: dvsym (nrx1s,nrx2s,nrx3s, 3, 3)
  real(DP), allocatable :: aux (:,:,:,:,:)
  ! the function to symmetrize
  ! auxiliary space

  integer :: ix, jx, kx, ri, rj, rk, irot, ip, jp, lp, mp, iflag
  ! define a real-space point on the grid
  ! the rotated points
  ! counter on symmetries
  ! counter on polarizations
  real(dp) :: det(48), sc(3,3), d

  if (nsym.eq.1) return
  allocate (aux(nrx1s,nrx2s,nrx3s,3,3))

  call dcopy (nrx1s*nrx2s*nrx3s* 9, dvsym, 1, aux, 1)
  
  ! compute determinants of transformation matrixes
  do irot = 1, nsym
    if (iflag == 1) then  ! pseudo-tensor
      sc(:,:) = dble(s(:,:,irot))
      ! crystal to cartesian
      call crys_to_cart (sc)
      d = sc(1,1)*sc(2,2)*sc(3,3) + &
          sc(1,2)*sc(2,3)*sc(3,1) + &
          sc(1,3)*sc(2,1)*sc(3,2) - &
          sc(1,3)*sc(2,2)*sc(3,1) - &
          sc(1,2)*sc(2,1)*sc(3,3) - &
          sc(1,1)*sc(2,3)*sc(3,2)
      det(irot) = sign(1.d0,d)
    else ! tensor
      det(irot) = 1.d0
    endif
  enddo

  dvsym (:,:,:,:,:) = 0.d0
  !
  !  symmmetrize 
  !
  do kx = 1, nr3s
  do jx = 1, nr2s
  do ix = 1, nr1s
     do irot = 1, nsym
        call ruotaijk(s (1, 1, irot), ftau (1, irot), ix, jx, kx, &
                      nr1s, nr2s, nr3s, ri, rj, rk)
        !
        ! ruotaijk finds the rotated of ix,jx,kx with the inverse of S
        !
        do ip = 1, 3
        do jp = 1, 3
           do lp = 1, 3
           do mp = 1, 3
              dvsym (ix, jx, kx, ip, jp) = &
              dvsym (ix, jx, kx, ip, jp) + det(irot)*&
                 DBLE (s (ip, lp, irot))* &
                 DBLE (s (jp, mp, irot))* &
                 aux (ri, rj, rk, lp, mp)
           enddo
           enddo
        enddo
        enddo
     enddo
  enddo
  enddo
  enddo

  call dscal (nrx1s*nrx2s*nrx3s*9, 1.d0 / DBLE (nsym), dvsym , 1)

  deallocate (aux)
  return
end subroutine syme2


