! $Id: mpicomm.f90,v 1.17 2002-05-21 06:57:31 brandenb Exp $

!!!!!!!!!!!!!!!!!!!!!
!!!  mpicomm.f90  !!!
!!!!!!!!!!!!!!!!!!!!!

!!! Module with MPI stuff

! NB: This was previously called mpicommyz.f90 and distributes in two
! directions.

! NNB: The boundary conditions ibc(j) are not yet implemented (as opposed
! to nompicomm)

module Mpicomm

  use Cparam
  use Cdata, only: lroot

  implicit none

  interface mpibcast_real		! Overload the `mpibcast_real' function
    module procedure mpibcast_real_scl
    module procedure mpibcast_real_arr
  endinterface

  include 'mpif.h'
 
  integer, parameter :: nbufy=nx*nz*nghost*mvar
  integer, parameter :: nbufz=nx*ny*nghost*mvar
  integer, parameter :: nbufyz=nx*nghost*nghost*mvar

  real, dimension (nx,nghost,nz,mvar) :: lbufyi,ubufyi,lbufyo,ubufyo
  real, dimension (nx,ny,nghost,mvar) :: lbufzi,ubufzi,lbufzo,ubufzo
  real, dimension (nx,nghost,nghost,mvar) :: llbufi,lubufi,uubufo,ulbufo
  integer, dimension (ny*nz) :: mm,nn
  integer :: ierr,imn
  integer :: nprocs,iproc,root=0
  integer :: ipx,ipy,ipz
  integer :: tolowy=3,touppy=4,tolowz=5,touppz=6 ! msg. tags
  integer :: tocornzz=7,cornyz=8,cornyy=9,cornzy=10 ! msg. tags for corners
  integer :: isend_rq_tolowy,isend_rq_touppy,irecv_rq_fromlowy,irecv_rq_fromuppy
  integer :: isend_rq_tolowz,isend_rq_touppz,irecv_rq_fromlowz,irecv_rq_fromuppz
  integer :: isend_rq_TOll,isend_rq_TOul,isend_rq_TOuu,isend_rq_TOlu  !!(corners)
  integer :: irecv_rq_FRuu,irecv_rq_FRlu,irecv_rq_FRll,irecv_rq_FRul  !!(corners)
  integer, dimension(MPI_STATUS_SIZE) :: isend_stat_tl,isend_stat_tu
  integer, dimension(MPI_STATUS_SIZE) :: irecv_stat_fl,irecv_stat_fu
  integer :: ylneigh,zlneigh ! `lower' neighbours
  integer :: yuneigh,zuneigh ! `upper' neighbours
  integer :: llcorn,lucorn,uucorn,ulcorn !!(the 4 corners in yz-plane)
  logical, dimension (ny*nz) :: necessary=.false.

  contains

!***********************************************************************
    subroutine mpicomm_init()
!
!  Initialise MPI communication and set up some variables
!  The arrays leftneigh and rghtneigh give the processor numbers
!  to the left and to the right.
!
!  20-aug-01/wolf: coded
!  31-aug-01/axel: added to 3-D
!  15-sep-01/axel: adapted from Wolfgang's version
!  21-may-02/axel: communication of corners added
!
      use General
      use Cdata, only: lmpicomm,directory
!
      integer :: i,m,n
      character (len=4) :: chproc
!
      lmpicomm = .true.
!
      call MPI_INIT(ierr)
      call MPI_COMM_SIZE(MPI_COMM_WORLD, nprocs, ierr)
      call MPI_COMM_RANK(MPI_COMM_WORLD, iproc , ierr)
      lroot = (iproc==root)
!
!  consistency checks
!
      if (nprocx /= 1) call stop_all('Inconsistency: nprocx > 1 not implemented')
      if (nprocs /= nprocy*nprocz) then
        if(lroot) then
          print*, 'Compiled with NCPUS = ', ncpus, &
          ', but running on ', nprocs, ' processors'
        endif
        STOP 'Inconsistency 1'
      endif
!
      if ((nprocy*ny /= nygrid) .or. &
          (nprocz*nz /= nzgrid)) then
        if(lroot) then
          write(0,'(A,2I4,A,2I4,A)') &
               'nproc[y-z]*n[y-z] = (', &
               nprocy*ny, nprocz*nz, &
               ') /= n[yz]grid= (', &
               nygrid, nzgrid, ")"
        endif
        call stop_all('Inconsistency 2')
      endif
!
!  position on the processor grid
!  x is fastest direction, z slowest
!
      ipx = 0
      ipy = modulo(iproc, nprocy)
      ipz = iproc/(nprocy)
!
!  set up `lower' and `upper' neighbours
!
      ylneigh = (ipz*nprocy+modulo(ipy-1,nprocy))
      yuneigh = (ipz*nprocy+modulo(ipy+1,nprocy))
      zlneigh = (modulo(ipz-1,nprocz)*nprocy+ipy)
      zuneigh = (modulo(ipz+1,nprocz)*nprocy+ipy)
!
!  set the four corners in the yz-plane (in cyclic order)
!
      llcorn=(modulo(ipz-1,nprocz)*nprocy+modulo(ipy-1,nprocy))
      lucorn=(modulo(ipz-1,nprocz)*nprocy+modulo(ipy+1,nprocy))
      uucorn=(modulo(ipz+1,nprocz)*nprocy+modulo(ipy+1,nprocy))
      ulcorn=(modulo(ipz+1,nprocz)*nprocy+modulo(ipy-1,nprocy))
!
!  this value is not yet the one read in, but the one initialized in cparam.f90
!
      if (ip<6) then
        print*,iproc,': ',ylneigh,llcorn,zlneigh,lucorn,yuneigh,uucorn,zuneigh,ulcorn
      endif
!
!  produce index-array for the sequence of points to be worked through:
!  first inner box (while communication of ghost values takes place),
!  then boundary zones.
!
      imn=1
      do n=n1i+1,n2i-1
        do m=m1i+1,m2i-1
          mm(imn)=m
          nn(imn)=n
          imn=imn+1
        enddo
      enddo
      necessary(imn)=.true.
!
!  do the lower stripe in the n-direction
!
      do n=n2i,n2
        do m=m1i+1,m2i-1
          mm(imn)=m
          nn(imn)=n
          imn=imn+1
        enddo
      enddo
!
!  upper stripe in the n-direction
!
      do n=n1,n1i
        do m=m1i+1,m2i-1
          mm(imn)=m
          nn(imn)=n
          imn=imn+1
        enddo
      enddo
!
!  left and right hand boxes
!
      do n=n1,n2
        do m=m1,m1i
          mm(imn)=m
          nn(imn)=n
          imn=imn+1
        enddo
        do m=m2i,m2
          mm(imn)=m
          nn(imn)=n
          imn=imn+1
        enddo
      enddo
!
!  produce a directory name for the output
!
      call chn(iproc,chproc)
      directory='tmp/proc'//chproc
!
    endsubroutine mpicomm_init
!***********************************************************************
    subroutine initiate_isendrcv_bdry(f)
!
!  Isend and Irecv boundary values. Called in the beginning of pde.
!  Does not wait for the receives to finish (done in finalise_isendrcv_bdry)
!  leftneigh and rghtneigh are initialized by mpicomm_init
!
!  21-may-02/axel: communication of corners added
!
      real, dimension (mx,my,mz,mvar) :: f
!
!  So far no distribution over x
!

!
!  Periodic boundary conditions in y
!
      if (nprocy>1) then
        lbufyo=f(l1:l2,m1:m1i,n1:n2,:)  !!(lower y-zone)
        ubufyo=f(l1:l2,m2i:m2,n1:n2,:)  !!(upper y-zone)
        call MPI_ISEND(lbufyo,nbufy,MPI_REAL,ylneigh,tolowy,MPI_COMM_WORLD,isend_rq_tolowy,ierr)
        call MPI_ISEND(ubufyo,nbufy,MPI_REAL,yuneigh,touppy,MPI_COMM_WORLD,isend_rq_touppy,ierr)
        call MPI_IRECV(ubufyi,nbufy,MPI_REAL,yuneigh,tolowy,MPI_COMM_WORLD,irecv_rq_fromuppy,ierr)
        call MPI_IRECV(lbufyi,nbufy,MPI_REAL,ylneigh,touppy,MPI_COMM_WORLD,irecv_rq_fromlowy,ierr)
      endif
!
!  Periodic boundary conditions in z
!
      if (nprocz>1) then
        lbufzo=f(l1:l2,m1:m2,n1:n1i,:)  !!(lower z-zone)
        ubufzo=f(l1:l2,m1:m2,n2i:n2,:)  !!(upper z-zone)
        call MPI_ISEND(lbufzo,nbufz,MPI_REAL,zlneigh,tolowz,MPI_COMM_WORLD,isend_rq_tolowz,ierr)
        call MPI_ISEND(ubufzo,nbufz,MPI_REAL,zuneigh,touppz,MPI_COMM_WORLD,isend_rq_touppz,ierr)
        call MPI_IRECV(ubufzi,nbufz,MPI_REAL,zuneigh,tolowz,MPI_COMM_WORLD,irecv_rq_fromuppz,ierr)
        call MPI_IRECV(lbufzi,nbufz,MPI_REAL,zlneigh,touppz,MPI_COMM_WORLD,irecv_rq_fromlowz,ierr)
      endif
!
!  The four corners (in counter-clockwise order)
!
      if (nprocy>1.and.nprocz>1) then
        llbufo=f(l1:l2,m1:m1i,n1:n1i,:)
        ulbufo=f(l1:l2,m2i:m2,n1:n1i,:)
        uubufo=f(l1:l2,m2i:m2,n2i:n2,:)
        lubufo=f(l1:l2,m1:m1i,n2i:n2,:)
        call MPI_ISEND(llbufo,nbufyz,MPI_REAL,llcorn,TOll,MPI_COMM_WORLD,isend_rq_TOll,ierr)
        call MPI_ISEND(ulbufo,nbufyz,MPI_REAL,ulcorn,TOul,MPI_COMM_WORLD,isend_rq_TOul,ierr)
        call MPI_ISEND(uubufo,nbufyz,MPI_REAL,uucorn,TOuu,MPI_COMM_WORLD,isend_rq_TOuu,ierr)
        call MPI_ISEND(lubufo,nbufyz,MPI_REAL,lucorn,TOlu,MPI_COMM_WORLD,isend_rq_TOlu,ierr)
        call MPI_IRECV(uubufi,nbufyz,MPI_REAL,uucorn,TOll,MPI_COMM_WORLD,irecv_rq_FRuu,ierr)
        call MPI_IRECV(lubufi,nbufyz,MPI_REAL,lucorn,TOul,MPI_COMM_WORLD,irecv_rq_FRlu,ierr)
        call MPI_IRECV(llbufi,nbufyz,MPI_REAL,llcorn,TOuu,MPI_COMM_WORLD,irecv_rq_FRll,ierr)
        call MPI_IRECV(ulbufi,nbufyz,MPI_REAL,ulcorn,TOlu,MPI_COMM_WORLD,irecv_rq_FRul,ierr)
      endif
!
    endsubroutine initiate_isendrcv_bdry
!***********************************************************************
    subroutine finalise_isendrcv_bdry(f)
!
!  Make sure the communications initiated with initiate_isendrcv_bdry are
!  finished and insert the just received boundary values.
!   Receive requests do not need to (and on OSF1 cannot) be explicitly
!  freed, since MPI_Wait takes care of this.
!
!  21-may-02/axel: communication of corners added
!
      use Boundcond

      real, dimension (mx,my,mz,mvar) :: f
      character (len=160) :: errmesg
!
!  1. wait until data received
!  2. set ghost zones
!  3. wait until send completed, will be overwritten in next time step
!
!  Communication in y (includes periodic bc)
!
      if (nprocy>1) then
        call MPI_WAIT(irecv_rq_fromuppy,irecv_stat_fu,ierr)
        call MPI_WAIT(irecv_rq_fromlowy,irecv_stat_fl,ierr)
        f(l1:l2, 1:m1-1,n1:n2,:)=lbufyi  !!(set lower buffer)
        f(l1:l2,m2+1:my,n1:n2,:)=ubufyi  !!(set upper buffer)
        call MPI_WAIT(isend_rq_tolowy,isend_stat_tl,ierr)
        call MPI_WAIT(isend_rq_touppy,isend_stat_tu,ierr)
      endif
!
!  Communication in z (includes periodic bc)
!
      if (nprocz>1) then
        call MPI_WAIT(irecv_rq_fromuppz,irecv_stat_fu,ierr)
        call MPI_WAIT(irecv_rq_fromlowz,irecv_stat_fl,ierr)
        f(l1:l2,m1:m2, 1:n1-1,:)=lbufzi  !!(set lower buffer)
        f(l1:l2,m1:m2,n2+1:mz,:)=ubufzi  !!(set upper buffer)
        call MPI_WAIT(isend_rq_tolowz,isend_stat_tl,ierr)
        call MPI_WAIT(isend_rq_touppz,isend_stat_tu,ierr)
      endif
!
!  The four yz-corners (in counter-clockwise order)
!
      if (nprocy>1.and.nprocz>1) then
        call MPI_WAIT(irecv_rq_FRuu,irecv_stat_Fuu,ierr)
        call MPI_WAIT(irecv_rq_FRlu,irecv_stat_Flu,ierr)
        call MPI_WAIT(irecv_rq_FRll,irecv_stat_Fll,ierr)
        call MPI_WAIT(irecv_rq_FRul,irecv_stat_Ful,ierr)
        f(l1:l2, 1:m1-1, 1:n1-1,:)=llbufi  !!(set ll corner)
        f(l1:l2,m2+1:my, 1:n1-1,:)=ulbufi  !!(set ul corner)
        f(l1:l2,m2+1:my,n2+1:mz,:)=uubufi  !!(set uu corner)
        f(l1:l2, 1:m1-1,n2+1:mz,:)=lubufi  !!(set lu corner)
        call MPI_WAIT(isend_rq_TOll,isend_stat_Tll,ierr)
        call MPI_WAIT(isend_rq_TOul,isend_stat_Tul,ierr)
        call MPI_WAIT(isend_rq_TOuu,isend_stat_Tuu,ierr)
        call MPI_WAIT(isend_rq_TOlu,isend_stat_Tlu,ierr)
      endif
!
!  Now do the boundary conditions
!  Periodic boundary conds. are what we get by default (communication has
!  already occured, which may sometimes be unnecessary)
!
      call boundconds(f,errmesg)
      if (errmesg /= "") call stop_it(trim(errmesg))
!
!  make sure the other precessors don't carry on sending new data
!  which could be mistaken for an earlier time
!
      call MPI_BARRIER(MPI_COMM_WORLD, ierr)
    endsubroutine finalise_isendrcv_bdry
!***********************************************************************
    subroutine mpibcast_int(ibcast_array,nbcast_array)
!
      integer :: nbcast_array
      integer, dimension(nbcast_array) :: ibcast_array
!
      call MPI_BCAST(ibcast_array,nbcast_array,MPI_INTEGER,root,MPI_COMM_WORLD,ierr)
    endsubroutine mpibcast_int
!***********************************************************************
    subroutine mpibcast_real_scl(bcast_array,nbcast_array)
!
      integer :: nbcast_array
      real :: bcast_array
!
!  is being used when nbcast_array=1 (eg when dt is being communicated)
!
      call MPI_BCAST(bcast_array,nbcast_array,MPI_REAL,root,MPI_COMM_WORLD,ierr)
    endsubroutine mpibcast_real_scl
!***********************************************************************
    subroutine mpibcast_real_arr(bcast_array,nbcast_array)
!
      integer :: nbcast_array
      real, dimension(nbcast_array) :: bcast_array
!
!  this works for the general case when nbcast_array is not 1
!
      call MPI_BCAST(bcast_array,nbcast_array,MPI_REAL,root,MPI_COMM_WORLD,ierr)
    endsubroutine mpibcast_real_arr
!***********************************************************************
    subroutine mpireduce_max(fmax_tmp,fmax,nreduce)
!
      integer :: nreduce
      real, dimension(nreduce) :: fmax_tmp,fmax
!
!  calculate total maximum for each array element and return to root
!
      call MPI_REDUCE(fmax_tmp, fmax, nreduce, MPI_REAL, MPI_MAX, root, &
                      MPI_COMM_WORLD, ierr)
    endsubroutine mpireduce_max
!***********************************************************************
    subroutine mpireduce_sum(fsum_tmp,fsum,nreduce)
!
      integer :: nreduce
      real, dimension(nreduce) :: fsum_tmp,fsum
!
!  calculate total sum for each array element and return to root
!
      call MPI_REDUCE(fsum_tmp, fsum, nreduce, MPI_REAL, MPI_SUM, root, &
                      MPI_COMM_WORLD, ierr)
    endsubroutine mpireduce_sum
!***********************************************************************
    subroutine mpifinalize
      call MPI_BARRIER(MPI_COMM_WORLD, ierr)
      call MPI_FINALIZE(ierr)
    endsubroutine mpifinalize
!***********************************************************************
    subroutine stop_it(msg)
!
!  Print message and stop
!  6-nov-01/wolf: coded
!
      character (len=*) :: msg
!      
      if (lroot) write(0,'(A,A)') 'STOPPED: ', msg
      call mpifinalize
      STOP
    endsubroutine stop_it
!***********************************************************************

endmodule Mpicomm
