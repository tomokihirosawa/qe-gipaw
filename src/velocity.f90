! Copyright (C) 2001-2005 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!

! The velocity operator is composed of three terms:
! v(\epsilon) = (1/i)[r, H - \epsilon S] = p + (1/i)[r, V_NL] - \epsilon (1/i)[r, S]
!
! the three terms are calculated in the following routines 
! apply_p      => apply p to the wave functions
! apply_vel_NL => apply (1/i)[r,V_NL] or (1/i)[r,S] to the wave functions
!
! Finally, the apply_vel subroutine is a driver that applies the velocity operator
!

!-----------------------------------------------------------------------
SUBROUTINE apply_p(psi, p_psi, ik, ipol, q)
  !-----------------------------------------------------------------------
  !
  ! ... Apply the kinetic part of the velocity operator
  ! ... |p_psi> = (G+k+q/2)_{ipol} |psi>
  !  
  USE kinds,                ONLY : DP
  USE klist,                ONLY : xk
  USE wvfct,                ONLY : nbnd, npwx, npw, igk  
  USE pwcom
  USE gipaw_module

  !-- parameters ---------------------------------------------------------
  IMPLICIT none
  INTEGER, INTENT(IN) :: ik               ! k-point
  INTEGER, INTENT(IN) :: ipol             ! cartesian direction (1..3)
  REAL(DP), INTENT(IN) :: q(3)
  COMPLEX(DP), INTENT(IN) :: psi(npwx,nbnd)
  COMPLEX(DP), INTENT(OUT) :: p_psi(npwx,nbnd)

  !-- local variables ----------------------------------------------------
  REAL(DP) :: gk
  INTEGER :: ig, ibnd

  do ibnd = 1, nbnd_occ(ik)
    do ig = 1, npw
      gk = xk(ipol,ik) + g(ipol,igk(ig)) + q(ipol)
      p_psi(ig,ibnd) = p_psi(ig,ibnd) + gk * tpiba * psi(ig,ibnd)
    enddo
  enddo

END SUBROUTINE apply_p

 
!-----------------------------------------------------------------------
SUBROUTINE apply_vel_NL(what, psi, vel_psi, ik, ipol, q)
  !-----------------------------------------------------------------------
  !
  ! ... Apply (what = 'V') the non-local part of the velocity operator:
  ! ...   (1/i)[r,V_NL] => dV^{NL}_{k+q,k}/dk
  ! ... here we use Hartree atomic units, so that:
  ! ...   V^{NL} => V^{NL} * ryd_to_hartree
  ! ...
  ! ... or (what = 'S') the ultrasoft contribution:
  ! ...   (1/i)[r,S] => dS_{k+q,k}/dk
  !-----------------------------------------------------------------------
  USE kinds,                ONLY : DP
  USE ions_base,            ONLY : nat, ityp, ntyp => nsp
  USE klist,                ONLY : xk
  USE wvfct,                ONLY : nbnd, npwx, npw, igk  
  USE becmod,               ONLY : bec_type, becp, calbec, &
                                   allocate_bec_type, deallocate_bec_type
  USE uspp,                 ONLY : nkb, vkb
  USE cell_base,            ONLY : tpiba
  USE gipaw_module,         ONLY : q_gipaw, nbnd_occ

  !-- paramters ----------------------------------------------------------
  IMPLICIT NONE
  CHARACTER, INTENT(IN) :: what     ! 'S' or 'V'
  INTEGER, INTENT(IN) :: ipol       ! cartesian direction (1..3)
  INTEGER, INTENT(IN) :: ik         ! k-point
  COMPLEX(DP), INTENT(IN) :: psi(npwx,nbnd)
  COMPLEX(DP), INTENT(OUT) :: vel_psi(npwx,nbnd)
  REAL(DP), INTENT(IN) :: q(3)

  !-- local variables ----------------------------------------------------
  real(dp), parameter :: ryd_to_hartree = 0.5d0
  complex(dp), allocatable :: aux(:,:), vkb_save(:,:)
  real(dp) :: dk, dxk(3)
  integer :: isign
  logical :: q_is_zero

  ! if no projectors, return
  if (nkb == 0) return

  ! set dk
  dk = q_gipaw/2.d0
  
  ! check if |q| is zero
  q_is_zero = .false.
  if (sqrt(q(1)*q(1)+q(2)*q(2)+q(3)*q(3)) < 1d-8) q_is_zero = .true.

  ! allocate temporary arrays, save old NL-potential
  call allocate_bec_type(nkb, nbnd_occ(ik), becp)
  allocate(aux(npwx,nbnd), vkb_save(npwx,nkb))
  vkb_save = vkb

  !====================================================================
  ! compute (1/2|dk|) ( V^{NL}_{k+dk+q,k+dk} |psi> - 
  !                     V^{NL}_{k-dk+q,k-dk} |psi> )
  ! or the same, with S.
  !====================================================================
  do isign = -1,1,2
      dxk(:) = xk(:,ik)
      dxk(ipol) = dxk(ipol) + isign * dk     ! k \pm dk

      ! compute <\beta(k \pm dk)| and project on |psi>
      call init_us_2_no_phase(npw, igk, dxk, vkb)
      call calbec (npw, vkb, psi, becp, nbnd_occ(ik))

      ! |q|!=0 => compute |\beta(k \pm dk + q)>
      if (.not. q_is_zero) then
          dxk(:) = dxk(:) + q(:)
          call init_us_2_no_phase(npw, igk, dxk, vkb)
      endif

      aux = (0.d0,0.d0)
      if (what == 'V' .or. what == 'v') then
          ! apply |\beta(k \pm dk+q)>D<\beta(k \pm dk)| to |psi>
          call add_vuspsi(npwx, npw, nbnd_occ(ik), aux)
          !! Hubbard? any other term here?
          vel_psi = vel_psi + dble(isign) * ryd_to_hartree * aux/(2.d0*dk*tpiba)

      elseif (what == 'S' .or. what == 's') then
          ! apply |\beta(k \pm dk+q)>S<\beta(k \pm dk)| to |psi>
          call s_psi(npwx, npw, nbnd_occ(ik), psi, aux)
          vel_psi = vel_psi + dble(isign) * aux/(2.d0*dk*tpiba)
      else
          call errore('apply_vel_NL', '''what'' parameter has the wrong value', 1)
      endif 
  enddo

  ! restore NL-potential at k
  vkb = vkb_save
  
  ! free memory
  call deallocate_bec_type(becp)
  deallocate(aux, vkb_save)

END SUBROUTINE apply_vel_NL


!-----------------------------------------------------------------------
SUBROUTINE apply_vel(psi, vel_psi, ik, ipol, q)
  !-----------------------------------------------------------------------
  !
  ! ... Apply the velocity operator
  !-----------------------------------------------------------------------
  USE kinds,                ONLY : DP
  USE wvfct,                ONLY : nbnd, npwx, npw, igk, et 
  USE uspp,                 ONLY : nkb, vkb, okvan
  USE gipaw_module,         ONLY : nbnd_occ

  !-- paramters ----------------------------------------------------------
  IMPLICIT NONE
  INTEGER, INTENT(IN) :: ipol       ! cartesian direction (1..3)
  INTEGER, INTENT(IN) :: ik         ! k-point
  COMPLEX(DP), INTENT(IN) :: psi(npwx,nbnd)
  COMPLEX(DP), INTENT(OUT) :: vel_psi(npwx,nbnd)
  REAL(DP), INTENT(IN) :: q(3)

  !-- local variables ----------------------------------------------------
  integer :: ibnd
  real(dp), parameter :: ryd_to_hartree = 0.5d0

  call start_clock('apply_vel')

  if (okvan) then
      call apply_vel_NL('S', psi, vel_psi, ik, ipol, q)
      do ibnd = 1, nbnd_occ(ik)
          vel_psi(1:npwx,ibnd) = -et(ibnd,ik) * ryd_to_hartree * vel_psi(1:npwx,ibnd)
      enddo
  endif

  call apply_vel_NL('V', psi, vel_psi, ik, ipol, q)

  call apply_p(psi, vel_psi, ik, ipol, q)

  call stop_clock('apply_vel')

END SUBROUTINE apply_vel
