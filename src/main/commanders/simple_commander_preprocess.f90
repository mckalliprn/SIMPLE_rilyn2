! concrete commander: pre-processing routines
module simple_commander_preprocess
include 'simple_lib.f08'
use simple_binoris_io
use simple_builder,        only: builder
use simple_cmdline,        only: cmdline
use simple_parameters,     only: parameters, params_glob
use simple_commander_base, only: commander_base
use simple_image,          only: image
use simple_sp_project,     only: sp_project
use simple_qsys_env,       only: qsys_env
use simple_stack_io,       only: stack_io
use simple_qsys_funs
use simple_progress
    
implicit none
    
public :: preprocess_commander_stream
public :: preprocess_commander_distr
public :: preprocess_commander
public :: motion_correct_commander_distr
public :: motion_correct_commander
public :: gen_pspecs_and_thumbs_commander_distr
public :: gen_pspecs_and_thumbs_commander
public :: ctf_estimate_commander_distr
public :: ctf_estimate_commander
public :: map_cavgs_selection_commander
public :: map_cavgs_states_commander
public :: pick_commander_distr
public :: pick_commander
public :: multipick_commander
public :: extract_commander_distr
public :: extract_commander
public :: reextract_commander_distr
public :: reextract_commander
public :: pick_extract_commander
public :: make_pickrefs_commander
private
#include "simple_local_flags.inc"
    
    type, extends(commander_base) :: preprocess_commander_stream
      contains
        procedure :: execute      => exec_preprocess_stream
    end type preprocess_commander_stream
    
    type, extends(commander_base) :: preprocess_commander_distr
      contains
        procedure :: execute      => exec_preprocess_distr
    end type preprocess_commander_distr
    
    type, extends(commander_base) :: preprocess_commander
      contains
        procedure :: execute      => exec_preprocess
    end type preprocess_commander
    
    type, extends(commander_base) :: motion_correct_commander_distr
      contains
        procedure :: execute      => exec_motion_correct_distr
    end type motion_correct_commander_distr
    
    type, extends(commander_base) :: motion_correct_commander
      contains
        procedure :: execute      => exec_motion_correct
    end type motion_correct_commander
    
    type, extends(commander_base) :: gen_pspecs_and_thumbs_commander_distr
      contains
        procedure :: execute      => exec_gen_pspecs_and_thumbs_distr
    end type gen_pspecs_and_thumbs_commander_distr
    
    type, extends(commander_base) :: gen_pspecs_and_thumbs_commander
      contains
        procedure :: execute      => exec_gen_pspecs_and_thumbs
    end type gen_pspecs_and_thumbs_commander
    
    type, extends(commander_base) :: ctf_estimate_commander_distr
      contains
        procedure :: execute      => exec_ctf_estimate_distr
    end type ctf_estimate_commander_distr
    
    type, extends(commander_base) :: ctf_estimate_commander
      contains
        procedure :: execute      => exec_ctf_estimate
    end type ctf_estimate_commander
    
    type, extends(commander_base) :: map_cavgs_selection_commander
      contains
        procedure :: execute      => exec_map_cavgs_selection
    end type map_cavgs_selection_commander
    
    type, extends(commander_base) :: map_cavgs_states_commander
      contains
        procedure :: execute      => exec_map_cavgs_states
    end type map_cavgs_states_commander
    
    type, extends(commander_base) :: pick_commander_distr
      contains
        procedure :: execute      => exec_pick_distr
    end type pick_commander_distr
    
    type, extends(commander_base) :: pick_commander
      contains
        procedure :: execute      => exec_pick
    end type pick_commander
    
    type, extends(commander_base) :: multipick_commander
            contains
            procedure :: execute => exec_multipick
        end type multipick_commander
    
    type, extends(commander_base) :: extract_commander_distr
      contains
        procedure :: execute      => exec_extract_distr
    end type extract_commander_distr
    
    type, extends(commander_base) :: extract_commander
      contains
        procedure :: execute      => exec_extract
    end type extract_commander
    
    type, extends(commander_base) :: reextract_commander_distr
      contains
        procedure :: execute      => exec_reextract_distr
    end type reextract_commander_distr
    
    type, extends(commander_base) :: reextract_commander
      contains
        procedure :: execute      => exec_reextract
    end type reextract_commander
    
    type, extends(commander_base) :: pick_extract_commander
      contains
        procedure :: execute      => exec_pick_extract
    end type pick_extract_commander
    
    type, extends(commander_base) :: make_pickrefs_commander
      contains
        procedure :: execute      => exec_make_pickrefs
    end type make_pickrefs_commander
    
    
    contains
    
        subroutine exec_preprocess_stream( self, cline )
            use simple_moviewatcher,                only: moviewatcher
            use simple_starproject,                 only: starproject
            use simple_timer
            class(preprocess_commander_stream), intent(inout) :: self
            class(cmdline),                     intent(inout) :: cline
            type(parameters)                       :: params
            integer,                   parameter   :: WAITTIME        = 5   ! folder watched every 5 seconds
            integer,                   parameter   :: LONGTIME        = 300  ! time lag after which a movie is processed
            integer,                   parameter   :: INACTIVE_TIME   = 900  ! inactive time trigger for writing project file
            ! integer,                   parameter   :: INACTIVE_TIME   = 300  ! dev setting
            logical,                   parameter   :: DEBUG_HERE      = .false.
            character(len=STDLEN),     parameter   :: micspproj_fname = './streamdata.simple'
            class(cmdline),            allocatable :: completed_jobs_clines(:), failed_jobs_clines(:)
            type(qsys_env)                         :: qenv
            type(cmdline)                          :: cline_make_pickrefs
            type(moviewatcher)                     :: movie_buff
            type(sp_project)                       :: spproj, stream_spproj
            type(starproject)                      :: starproj
            character(len=LONGSTRLEN), allocatable :: movies(:), completed_fnames(:)
            character(len=:),          allocatable :: output_dir, output_dir_ctf_estimate, output_dir_picker
            character(len=:),          allocatable :: output_dir_motion_correct, output_dir_extract
            character(len=LONGSTRLEN)              :: movie
            real                                   :: pickref_scale
            integer                                :: nmovies, imovie, stacksz, prev_stacksz, iter, last_injection
            integer                                :: cnt, n_imported, nptcls_glob, n_failed_jobs, n_fail_iter
            logical                                :: l_pick, l_movies_left, l_haschanged
            integer(timer_int_kind) :: t0
            real(timer_int_kind)    :: rt_write
            if( .not. cline%defined('oritype')         )  call cline%set('oritype',        'mic')
            if( .not. cline%defined('mkdir')           )  call cline%set('mkdir',          'yes')
            ! motion correction
            if( .not. cline%defined('trs')             )  call cline%set('trs',              20.)
            if( .not. cline%defined('lpstart')         )  call cline%set('lpstart',           8.)
            if( .not. cline%defined('lpstop')          )  call cline%set('lpstop',            5.)
            if( .not. cline%defined('bfac')            )  call cline%set('bfac',             50.)
            if( .not. cline%defined('groupframes')     )  call cline%set('groupframes',     'no')
            if( .not. cline%defined('mcconvention')    )  call cline%set('mcconvention','simple')
            if( .not. cline%defined('eer_upsampling')  )  call cline%set('eer_upsampling',    1.)
            if( .not. cline%defined('mcpatch')         )  call cline%set('mcpatch',        'yes')
            if( .not. cline%defined('mcpatch_thres')   )  call cline%set('mcpatch_thres',  'yes')
            if( .not. cline%defined('algorithm')       )  call cline%set('algorithm',    'patch')
            ! ctf estimation
            if( .not. cline%defined('pspecsz')         )  call cline%set('pspecsz',          512.)
            if( .not. cline%defined('hp_ctf_estimate') )  call cline%set('hp_ctf_estimate',  HP_CTF_ESTIMATE)
            if( .not. cline%defined('lp_ctf_estimate') )  call cline%set('lp_ctf_estimate',  LP_CTF_ESTIMATE)
            if( .not. cline%defined('dfmin')           )  call cline%set('dfmin',            DFMIN_DEFAULT)
            if( .not. cline%defined('dfmax')           )  call cline%set('dfmax',            DFMAX_DEFAULT)
            if( .not. cline%defined('ctfpatch')        )  call cline%set('ctfpatch',         'yes')
            if( .not. cline%defined('ctfresthreshold') )  call cline%set('ctfresthreshold',  CTFRES_THRESHOLD)
            if( .not. cline%defined('icefracthreshold') ) call cline%set('icefracthreshold', ICEFRAC_THRESHOLD)
            ! picking
            if( .not. cline%defined('lp_pick')         )  call cline%set('lp_pick',          20.)
            ! extraction
            if( .not. cline%defined('pcontrast')       )  call cline%set('pcontrast',    'black')
            if( .not. cline%defined('extractfrommov')  )  call cline%set('extractfrommov',  'no')
            call cline%set('numlen', 5.)
            call cline%set('stream','yes')
            ! master parameters
            call params%new(cline)
            params_glob%split_mode = 'stream'
            params_glob%ncunits    = params%nparts
            call cline%set('mkdir', 'no')
            call cline%set('prg',   'preprocess')
            if( cline%defined('dir_prev') .and. .not.file_exists(params%dir_prev) )then
                THROW_HARD('Directory '//trim(params%dir_prev)//' does not exist!')
            endif
            ! master project file
            call spproj%read( params%projfile )
            call spproj%update_projinfo(cline)
            if( spproj%os_mic%get_noris() /= 0 ) THROW_HARD('PREPROCESS_STREAM must start from an empty project (eg from root project folder)')
            ! picking
            l_pick = .false.
            if( cline%defined('pickrefs') ) l_pick = .true.
            ! output directories
            output_dir = PATH_HERE
            output_dir_ctf_estimate   = filepath(trim(output_dir), trim(DIR_CTF_ESTIMATE))
            output_dir_motion_correct = filepath(trim(output_dir), trim(DIR_MOTION_CORRECT))
            call simple_mkdir(output_dir_ctf_estimate,errmsg="commander_stream_wflows :: exec_preprocess_stream;  ")
            call simple_mkdir(output_dir_motion_correct,errmsg="commander_stream_wflows :: exec_preprocess_stream;  ")
            if( l_pick )then
                output_dir_picker  = filepath(trim(output_dir), trim(DIR_PICKER))
                output_dir_extract = filepath(trim(output_dir), trim(DIR_EXTRACT))
                call simple_mkdir(output_dir_picker,errmsg="commander_stream_wflows :: exec_preprocess_stream;  ")
                call simple_mkdir(output_dir_extract,errmsg="commander_stream_wflows :: exec_preprocess_stream;  ")
            endif
            ! setup the environment for distributed execution
            call qenv%new(1,stream=.true.)
            ! prepares picking references
            if( l_pick )then
                if( trim(params%picker).eq.'old' )then
                    cline_make_pickrefs = cline
                    call cline_make_pickrefs%set('prg','make_pickrefs')
                    call cline_make_pickrefs%set('stream','no')
                    if( cline_make_pickrefs%defined('eer_upsampling') )then
                        pickref_scale = real(params%eer_upsampling) * params%scale
                        call cline_make_pickrefs%set('scale',pickref_scale)
                    endif
                    call qenv%exec_simple_prg_in_queue(cline_make_pickrefs, 'MAKE_PICKREFS_FINISHED')
                    call cline%set('pickrefs', trim(PICKREFS)//params%ext)
                    write(logfhandle,'(A)')'>>> PREPARED PICKING TEMPLATES'
                endif
            endif
            ! movie watcher init
            movie_buff = moviewatcher(LONGTIME)
            ! import previous runs
            nptcls_glob = 0
            call import_prev_streams
            ! start watching
            last_injection = simple_gettime()
            prev_stacksz  = 0
            nmovies       = 0
            iter          = 0
            n_imported    = 0
            n_failed_jobs = 0
            l_movies_left = .false.
            l_haschanged  = .false.
            do
                ! termination & pausing
                if( file_exists(trim(TERM_STREAM)) )then
                    write(logfhandle,'(A)')'>>> TERMINATING PREPROCESS STREAM'
                    exit
                endif
                iter = iter + 1
                call movie_buff%watch( nmovies, movies )
                ! append movies to processing stack
                if( nmovies > 0 )then
                    cnt = 0
                    do imovie = 1, nmovies
                        movie = trim(adjustl(movies(imovie)))
                        if( movie_buff%is_past(movie) )cycle
                        call create_individual_project(movie)
                        call qenv%qscripts%add_to_streaming( cline )
                        call qenv%qscripts%schedule_streaming( qenv%qdescr )
                        call movie_buff%add2history( movies(imovie) )
                        cnt = cnt+1
                        if( cnt == min(params%nparts,nmovies) ) exit
                    enddo
                    l_movies_left = cnt .ne. nmovies
                else
                    l_movies_left = .false.
                endif
                ! stream scheduling
                call submit_jobs
                ! fetch completed jobs list & updates of cluster2D_stream
                if( qenv%qscripts%get_done_stacksz() > 0 )then
                    call qenv%qscripts%get_stream_done_stack( completed_jobs_clines )
                    call update_projects_list( completed_fnames, n_imported )
                    do cnt = 1,size(completed_jobs_clines)
                        call completed_jobs_clines(cnt)%kill
                    enddo
                    deallocate(completed_jobs_clines)
                else
                    n_imported = 0 ! newly imported
                endif
                ! failed jobs
                if( qenv%qscripts%get_failed_stacksz() > 0 )then
                    call qenv%qscripts%get_stream_fail_stack( failed_jobs_clines, n_fail_iter )
                    if( n_fail_iter > 0 )then
                        n_failed_jobs = n_failed_jobs + n_fail_iter
                        do cnt = 1,n_fail_iter
                            call failed_jobs_clines(cnt)%kill
                        enddo
                        deallocate(failed_jobs_clines)
                    endif
                endif
                ! project update
                if( n_imported > 0 )then
                    n_imported = spproj%os_mic%get_noris()
                    write(logfhandle,'(A,I5)')                         '>>> # MOVIES PROCESSED & IMPORTED    : ',n_imported
                    if( l_pick ) write(logfhandle,'(A,I8)')            '>>> # PARTICLES EXTRACTED            : ',nptcls_glob
                    write(logfhandle,'(A,I3,A1,I3)')                   '>>> # OF COMPUTING UNITS IN USE/TOTAL: ',qenv%get_navail_computing_units(),'/',params%nparts
                    if( n_failed_jobs > 0 ) write(logfhandle,'(A,I5)') '>>> # FAILED JOBS                    : ',n_failed_jobs
                    ! write project for gui, micrographs field only
                    call spproj%write(micspproj_fname)
                    last_injection = simple_gettime()
                    l_haschanged   = .true.
                    n_imported     = spproj%os_mic%get_noris()
                else
                    ! wait
                    if( .not.l_movies_left )then
                        if( (simple_gettime()-last_injection > INACTIVE_TIME) .and. l_haschanged )then
                            ! write project when inactive...
                            call write_project
                            l_haschanged = .false.
                        else
                            ! ...or wait
                            call sleep(WAITTIME)
                        endif
                    endif
                endif
            end do
            ! termination
            call write_project
            call spproj%kill
            ! cleanup
            call qsys_cleanup
            call del_file(micspproj_fname)
            ! end gracefully
            call simple_end('**** SIMPLE_PREPROCESS_STREAM NORMAL STOP ****')
            contains
    
                subroutine write_project()
                    logical, allocatable :: stk_mask(:)
                    integer, allocatable :: states(:)
                    integer              :: iproj,nptcls,istk,fromp,top,i,iptcl,nstks,n,nmics
                    write(logfhandle,'(A)')'>>> PROJECT UPDATE'
                    nmics = spproj%os_mic%get_noris()
                    call spproj%write_segment_inside('mic', params%projfile)
                    if( l_pick )then
                        if( DEBUG_HERE ) t0 = tic()
                        ! stacks
                        allocate(stk_mask(nmics))
                        allocate(states(nmics))
                        do iproj = 1,nmics
                            stk_mask(iproj) = nint(spproj%os_mic%get(iproj,'nptcls')) > 0
                            states(iproj)   = spproj%os_mic%get_state(iproj)
                        enddo
                        nstks = count(stk_mask)
                        call spproj%os_stk%new(nstks, is_ptcl=.false.)
                        nptcls = 0
                        istk   = 0
                        fromp  = 0
                        top    = 0
                        do iproj = 1,nmics
                            if( .not.stk_mask(iproj) ) cycle
                            istk = istk+1
                            call stream_spproj%read_segment('stk', completed_fnames(iproj))
                            call stream_spproj%os_stk%set_state(1, states(iproj))
                            n      = nint(stream_spproj%os_stk%get(1,'nptcls'))
                            fromp  = nptcls + 1
                            nptcls = nptcls + n
                            top    = nptcls
                            call spproj%os_stk%transfer_ori(istk,stream_spproj%os_stk,1)
                            call spproj%os_stk%set(istk, 'fromp',real(fromp))
                            call spproj%os_stk%set(istk, 'top',  real(top))
                        enddo
                        call spproj%write_segment_inside('stk', params%projfile)
                        call spproj%os_stk%kill
                        ! particles
                        call spproj%os_ptcl2D%new(nptcls, is_ptcl=.true.)
                        istk   = 0
                        iptcl  = 0
                        do iproj = 1,nmics
                            if( .not.stk_mask(iproj) ) cycle
                            istk = istk+1
                            call stream_spproj%read_segment('ptcl2D', completed_fnames(iproj))
                            nptcls = stream_spproj%os_ptcl2D%get_noris()
                            do i = 1,nptcls
                                iptcl = iptcl + 1
                                call spproj%os_ptcl2D%transfer_ori(iptcl,stream_spproj%os_ptcl2D,i)
                                call spproj%os_ptcl2D%set(iptcl, 'stkind', real(istk))
                                call spproj%os_ptcl2D%set_state(iptcl, states(iproj))
                            enddo
                            call stream_spproj%kill
                        enddo
                        write(logfhandle,'(A,I8)')'>>> # PARTICLES EXTRACTED:         ',spproj%os_ptcl2D%get_noris()
                        call spproj%write_segment_inside('ptcl2D', params%projfile)
                        spproj%os_ptcl3D = spproj%os_ptcl2D
                        call spproj%os_ptcl2D%kill
                        call spproj%os_ptcl3D%delete_2Dclustering
                        call spproj%write_segment_inside('ptcl3D', params%projfile)
                        call spproj%os_ptcl3D%kill
                    endif
                    call spproj%write_non_data_segments(params%projfile)
    
                    ! write starfile
                    if (spproj%os_mic%get_noris() > 0) then
                        if( file_exists("micrographs.star") ) call del_file("micrographs.star")
                        call starproj%assign_optics(cline, spproj)
                        call starproj%export_mics(cline, spproj)
                    end if
    
                    ! benchmark
                    if( DEBUG_HERE )then
                        rt_write = toc(t0)
                        print *,'rt_write  : ', rt_write; call flush(6)
                    endif
                end subroutine write_project
    
                subroutine submit_jobs
                    call qenv%qscripts%schedule_streaming( qenv%qdescr )
                    stacksz = qenv%qscripts%get_stacksz()
                    if( stacksz .ne. prev_stacksz )then
                        prev_stacksz = stacksz
                        write(logfhandle,'(A,I6)')'>>> MOVIES TO PROCESS:                ', stacksz
                    endif
                end subroutine submit_jobs
    
                ! returns list of completed jobs + updates for cluster2D_stream
                subroutine update_projects_list( completedfnames, nimported )
                    character(len=LONGSTRLEN), allocatable, intent(inout) :: completedfnames(:)
                    integer,                                intent(inout) :: nimported
                    type(sp_project)                       :: streamspproj
                    character(len=:),          allocatable :: fname, abs_fname
                    character(len=LONGSTRLEN), allocatable :: old_fnames(:)
                    logical, allocatable :: spproj_mask(:)
                    integer :: i, n_spprojs, n_old, nptcls_here, state, j, n2import, nprev_imports, n_completed
                    n_completed = 0
                    nimported   = 0
                    ! projects to import
                    n_spprojs = size(completed_jobs_clines)
                    if( n_spprojs == 0 )return
                    allocate(spproj_mask(n_spprojs),source=.true.)
                    ! previously completed projects
                    n_old = 0 ! on first import
                    if( allocated(completedfnames) ) n_old = size(completed_fnames)
                    do i = 1,n_spprojs
                        ! flags zero-picked mics that will not be imported
                        fname = trim(output_dir)//trim(completed_jobs_clines(i)%get_carg('projfile'))
                        call check_nptcls(fname, nptcls_here, state, l_pick)
                        if( l_pick )then
                            spproj_mask(i) = (nptcls_here > 0) .and. (state > 0)
                        else
                            spproj_mask(i) = state > 0
                        endif
                    enddo
                    n2import      = count(spproj_mask)
                    n_failed_jobs = n_failed_jobs + (n_spprojs-n2import)
                    if( l_pick .and. n2import /= n_spprojs )then
                        write(logfhandle,'(A,I3,A)')'>>> NO PARTICLES FOUND IN ',n_spprojs-n2import,' MICROGRAPH(S)'
                    endif
                    if( n2import > 0 )then
                        n_completed = n_old + n2import
                        nimported   = n2import
                        nprev_imports = spproj%os_mic%get_noris()
                        if( nprev_imports == 0 )then
                            call spproj%os_mic%new(n2import, is_ptcl=.false.) ! first time
                            allocate(completedfnames(n_completed))
                        else
                            call spproj%os_mic%reallocate(n_completed)
                            old_fnames = completed_fnames(:)
                            deallocate(completed_fnames)
                            allocate(completedfnames(n_completed))
                            if( n_old > 0 )then
                                completedfnames(1:n_old) = old_fnames(:)
                            endif
                            deallocate(old_fnames)
                        endif
                        j = 0
                        nptcls_here = 0
                        do i=1,n_spprojs
                            if( .not.spproj_mask(i) ) cycle
                            j = j+1
                            fname     = trim(completed_jobs_clines(i)%get_carg('projfile'))
                            abs_fname = simple_abspath(fname, errmsg='preprocess_stream :: update_projects_list 1')
                            completedfnames(n_old+j) = trim(abs_fname)
                            call streamspproj%read_segment('mic', abs_fname)
                            if( l_pick ) nptcls_here = nptcls_here + nint(streamspproj%os_mic%get(1,'nptcls'))
                            call spproj%os_mic%transfer_ori(n_old+j, streamspproj%os_mic, 1)
                            call streamspproj%kill
                        enddo
                        if( l_pick ) nptcls_glob = nptcls_glob + nptcls_here
                    else
                        nimported  = 0
                        return
                    endif
                    call write_filetable(STREAM_SPPROJFILES, completedfnames)
                end subroutine update_projects_list
    
                subroutine create_individual_project( movie )
                    character(len=*), intent(in) :: movie
                    type(sp_project)             :: spproj_here
                    type(cmdline)                :: cline_here
                    type(ctfparams)              :: ctfvars
                    character(len=STDLEN)        :: ext, movie_here
                    character(len=LONGSTRLEN)    :: projname, projfile
                    movie_here = basename(trim(movie))
                    ext        = fname2ext(trim(movie_here))
                    projname   = trim(PREPROCESS_PREFIX)//trim(get_fbody(trim(movie_here), trim(ext)))
                    projfile   = trim(projname)//trim(METADATA_EXT)
                    call cline_here%set('projname', trim(projname))
                    call cline_here%set('projfile', trim(projfile))
                    call spproj_here%update_projinfo(cline_here)
                    spproj_here%compenv  = spproj%compenv
                    spproj_here%jobproc  = spproj%jobproc
                    ctfvars%ctfflag      = CTFFLAG_YES
                    ctfvars%smpd         = params%smpd
                    ctfvars%cs           = params%cs
                    ctfvars%kv           = params%kv
                    ctfvars%fraca        = params%fraca
                    ctfvars%l_phaseplate = params%phaseplate.eq.'yes'
                    call spproj_here%add_single_movie(trim(movie), ctfvars)
                    call spproj_here%write
                    call spproj_here%kill
                    call cline%set('projname', trim(projname))
                    call cline%set('projfile', trim(projfile))
                end subroutine create_individual_project
    
                subroutine remove_individual_projects
                    character(len=LONGSTRLEN), allocatable :: spproj_fnames(:)
                    integer :: i, n
                    if( .not.file_exists(STREAM_SPPROJFILES) )return
                    call read_filetable(STREAM_SPPROJFILES, spproj_fnames)
                    n = size(spproj_fnames)
                    do i = 1,n
                        call del_file(spproj_fnames(i))
                    enddo
                end subroutine remove_individual_projects
    
                !>  import previous run to the current project based on past single project files
                subroutine import_prev_streams
                    type(sp_project) :: streamspproj
                    type(ori)        :: o, o_stk
                    character(len=LONGSTRLEN), allocatable :: sp_files(:)
                    character(len=:), allocatable :: mic, mov
                    logical,          allocatable :: spproj_mask(:)
                    integer :: iproj,nprojs,icnt,nptcls
                    logical :: err
                    if( .not.cline%defined('dir_prev') ) return
                    err = .false.
                    call simple_list_files_regexp(params%dir_prev,'^'//trim(PREPROCESS_PREFIX)//'.*\.simple$',sp_files)
                    nprojs = size(sp_files)
                    if( nprojs < 1 ) return
                    allocate(spproj_mask(nprojs),source=.false.)
                    nptcls = 0
                    do iproj = 1,nprojs
                        call streamspproj%read_segment('mic', sp_files(iproj) )
                        if( streamspproj%os_mic%get_noris() /= 1 )then
                            THROW_WARN('Ignoring '//trim(sp_files(iproj)))
                            cycle
                        endif
                        if( .not. streamspproj%os_mic%isthere(1,'intg') )cycle
                        if( l_pick )then
                            if( streamspproj%os_mic%get(1,'nptcls') < 0.5 )cycle
                        endif
                        spproj_mask(iproj) = .true.
                    enddo
                    if( count(spproj_mask) == 0 )then
                        nptcls_glob = 0
                        return
                    endif
                    icnt = 0
                    do iproj = 1,nprojs
                        if( .not.spproj_mask(iproj) )cycle
                        call streamspproj%read_segment('mic',sp_files(iproj))
                        call streamspproj%os_mic%get_ori(1, o)
                        ! import mic segment
                        call movefile2folder('intg',        output_dir_motion_correct, o, err)
                        call movefile2folder('forctf',      output_dir_motion_correct, o, err)
                        call movefile2folder('thumb',       output_dir_motion_correct, o, err)
                        call movefile2folder('mc_starfile', output_dir_motion_correct, o, err)
                        call movefile2folder('mceps',       output_dir_motion_correct, o, err)
                        call movefile2folder('ctfjpg',      output_dir_ctf_estimate,   o, err)
                        call movefile2folder('ctfdoc',      output_dir_ctf_estimate,   o, err)
                        if( l_pick )then
                            ! import mic & updates stk segment
                            call movefile2folder('boxfile', output_dir_picker, o, err)
                            nptcls = nptcls + nint(o%get('nptcls'))
                            call streamspproj%os_mic%set_ori(1, o)
                            if( .not.err )then
                                call streamspproj%read_segment('stk', sp_files(iproj))
                                if( streamspproj%os_stk%get_noris() == 1 )then
                                    call streamspproj%os_stk%get_ori(1, o_stk)
                                    call movefile2folder('stk', output_dir_extract, o_stk, err)
                                    call streamspproj%os_stk%set_ori(1, o_stk)
                                    call streamspproj%read_segment('ptcl2D', sp_files(iproj))
                                    call streamspproj%read_segment('ptcl3D', sp_files(iproj))
                                endif
                            endif
                        else
                            ! import mic segment
                            call streamspproj%os_mic%set_ori(1, o)
                        endif
                        ! add to history
                        call o%getter('movie', mov)
                        call o%getter('intg', mic)
                        call movie_buff%add2history(mov)
                        call movie_buff%add2history(mic)
                        ! write updated individual project file
                        call streamspproj%write(basename(sp_files(iproj)))
                        ! count
                        icnt = icnt + 1
                    enddo
                    if( icnt > 0 )then
                        ! updating STREAM_SPPROJFILES for Cluster2D_stream
                        allocate(completed_jobs_clines(icnt))
                        icnt = 0
                        do iproj = 1,nprojs
                            if(spproj_mask(iproj))then
                                icnt = icnt+1
                                call completed_jobs_clines(icnt)%set('projfile',basename(sp_files(iproj)))
                            endif
                        enddo
                        call update_projects_list(completed_fnames, n_imported)
                        deallocate(completed_jobs_clines)
                    endif
                    call o%kill
                    call o_stk%kill
                    call streamspproj%kill
                    write(*,'(A,I3)')'>>> IMPORTED PREVIOUS PROCESSED MOVIES: ', icnt
                end subroutine import_prev_streams
    
                subroutine check_nptcls( fname, nptcls, state, ptcl_check )
                    character(len=*), intent(in)  :: fname
                    integer,          intent(out) :: nptcls, state
                    logical,          intent(in)  :: ptcl_check
                    type(sp_project) :: spproj_here
                    integer :: nmics, nstks
                    state  = 0
                    call spproj_here%read_data_info(fname, nmics, nstks, nptcls)
                    if( ptcl_check )then
                        if( nmics /= 1 .or. nptcls < 1 )then
                            ! something went wrong, skipping this one
                            THROW_WARN('Something went wrong with: '//trim(fname)//'. Skipping')
                            nptcls = 0
                        else
                            call spproj_here%read_segment('mic',fname)
                            nptcls = nint(spproj_here%os_mic%get(1,'nptcls'))
                            state  = spproj_here%os_mic%get_state(1)
                            call spproj_here%kill
                        endif
                    else
                        if( nmics /= 1 )then
                            ! something went wrong, skipping this one
                            THROW_WARN('Something went wrong with: '//trim(fname)//'. Skipping')
                        else
                            call spproj_here%read_segment('mic',fname)
                            state  = spproj_here%os_mic%get_state(1)
                            call spproj_here%kill
                        endif
                    endif
                end subroutine check_nptcls
    
                subroutine movefile2folder(key, folder, o, err)
                    character(len=*), intent(in)    :: key, folder
                    class(ori),       intent(inout) :: o
                    logical,          intent(out)   :: err
                    character(len=:), allocatable :: src
                    character(len=LONGSTRLEN) :: dest,reldest
                    integer :: iostat
                    err = .false.
                    if( .not.o%isthere(key) )then
                        err = .true.
                        return
                    endif
                    call o%getter(key,src)
                    if( .not.file_exists(src) )then
                        err = .true.
                        return
                    endif
                    dest   = trim(folder)//'/'//basename(src)
                    iostat = rename(src,dest)
                    if( iostat /= 0 )then
                        THROW_WARN('Ignoring '//trim(src))
                        return
                    endif
                    iostat = rename(src,reldest)
                    call make_relativepath(CWD_GLOB,dest,reldest)
                    call o%set(key,reldest)
                end subroutine movefile2folder
    
        end subroutine exec_preprocess_stream
    
        subroutine exec_preprocess_distr( self, cline )
            class(preprocess_commander_distr), intent(inout) :: self
            class(cmdline),                    intent(inout) :: cline
            type(parameters)              :: params
            type(qsys_env)                :: qenv
            type(cmdline)                 :: cline_make_pickrefs
            type(chash)                   :: job_descr
            type(sp_project)              :: spproj
            real    :: pickref_scale
            logical :: l_pick
            if( .not. cline%defined('oritype')         ) call cline%set('oritype',        'mic')
            if( .not. cline%defined('stream')          ) call cline%set('stream',          'no')
            if( .not. cline%defined('mkdir')           ) call cline%set('mkdir',          'yes')
            ! mnotion correction
            if( .not. cline%defined('trs')             ) call cline%set('trs',              20.)
            if( .not. cline%defined('lpstart')         ) call cline%set('lpstart',           8.)
            if( .not. cline%defined('lpstop')          ) call cline%set('lpstop',            5.)
            if( .not. cline%defined('bfac')            ) call cline%set('bfac',             50.)
            if( .not. cline%defined('groupframes')     ) call cline%set('groupframes',     'no')
            if( .not. cline%defined('mcconvention')    ) call cline%set('mcconvention','simple')
            if( .not. cline%defined('eer_upsampling')  ) call cline%set('eer_upsampling',    1.)
            if( .not. cline%defined('mcpatch')         ) call cline%set('mcpatch',        'yes')
            if( .not. cline%defined('mcpatch_thres')   ) call cline%set('mcpatch_thres',  'yes')
            if( .not. cline%defined('algorithm')       ) call cline%set('algorithm',    'patch')
            ! ctf estimation
            if( .not. cline%defined('pspecsz')         ) call cline%set('pspecsz',         512.)
            if( .not. cline%defined('hp_ctf_estimate') ) call cline%set('hp_ctf_estimate',  30.)
            if( .not. cline%defined('lp_ctf_estimate') ) call cline%set('lp_ctf_estimate',   5.)
            if( .not. cline%defined('dfmin')           ) call cline%set('dfmin',          DFMIN_DEFAULT)
            if( .not. cline%defined('dfmax')           ) call cline%set('dfmax',          DFMAX_DEFAULT)
            if( .not. cline%defined('ctfpatch')        ) call cline%set('ctfpatch',       'yes')
            ! picking
            if( .not. cline%defined('picker')          ) call cline%set('picker',         'old')
            if( .not. cline%defined('lp_pick')         ) call cline%set('lp_pick',          20.)
            if( .not. cline%defined('ndev')            ) call cline%set('ndev',              2.)
            if( .not. cline%defined('thres')           ) call cline%set('thres',            24.)
            ! extraction
            if( .not. cline%defined('pcontrast')       ) call cline%set('pcontrast',    'black')
            if( .not. cline%defined('extractfrommov')  ) call cline%set('extractfrommov',  'no')
            call params%new(cline)
            ! set mkdir to no (to avoid nested directory structure)
            call cline%set('mkdir', 'no')
            ! read in movies
            call spproj%read(params%projfile)
            ! DISTRIBUTED EXECUTION
            params%nptcls = spproj%get_nmovies()
            if( params%nptcls == 0 )then
                THROW_HARD('no movie to process! exec_preprocess_distr')
            endif
            if( params%nparts > params%nptcls ) THROW_HARD('# partitions (nparts) must be < number of entries in filetable')
            ! deal with numlen so that length matches JOB_FINISHED indicator files
            params%numlen = len(int2str(params%nparts))
            call cline%set('numlen', real(params%numlen))
            ! setup the environment for distributed execution
            call qenv%new(params%nparts)
            ! prepares picking references
            l_pick = .false.
            if( cline%defined('pickrefs') )then
                if( trim(params%picker).eq.'old' )then
                    cline_make_pickrefs = cline
                    call cline_make_pickrefs%set('prg','make_pickrefs')
                    if( cline_make_pickrefs%defined('eer_upsampling') )then
                        pickref_scale = real(params%eer_upsampling) * params%scale
                        call cline_make_pickrefs%set('scale',pickref_scale)
                    endif
                    call qenv%exec_simple_prg_in_queue(cline_make_pickrefs, 'MAKE_PICKREFS_FINISHED')
                    call cline%set('pickrefs', trim(PICKREFS)//params%ext)
                    write(logfhandle,'(A)')'>>> PREPARED PICKING TEMPLATES'
                endif
                l_pick = .true.
            else if( cline%defined('moldiam') )then
                l_pick = .true.
            endif
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule & clean
            call qenv%gen_scripts_and_schedule_jobs(job_descr, algnfbody=trim(ALGN_FBODY), array=L_USE_SLURM_ARR)
            ! merge docs
            call spproj%read(params%projfile)
            call spproj%update_projinfo(cline)
            call spproj%write_segment_inside('projinfo')
            call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
            call spproj%kill
            ! cleanup
            call qsys_cleanup
            ! end gracefully
            call simple_end('****REPROCESS NORMAL STOP ****')
        end subroutine exec_preprocess_distr
    
        subroutine exec_preprocess( self, cline )
            use simple_sp_project,          only: sp_project
            use simple_motion_correct_iter, only: motion_correct_iter
            use simple_ctf_estimate_iter,   only: ctf_estimate_iter
            use simple_picker_iter,         only: picker_iter
            class(preprocess_commander), intent(inout) :: self
            class(cmdline),              intent(inout) :: cline
            type(parameters)              :: params
            type(ori)                     :: o_mov
            type(ctf_estimate_iter)       :: ctfiter
            type(motion_correct_iter)     :: mciter
            type(picker_iter)             :: piter
            type(extract_commander)       :: xextract
            type(cmdline)                 :: cline_extract
            type(sp_project)              :: spproj
            type(ctfparams)               :: ctfvars
            character(len=:), allocatable :: imgkind, moviename, output_dir_picker, fbody
            character(len=:), allocatable :: moviename_forctf, moviename_intg, output_dir_motion_correct
            character(len=:), allocatable :: output_dir_ctf_estimate, output_dir_extract
            character(len=LONGSTRLEN)     :: boxfile
            real    :: smpd_pick
            integer :: nmovies, fromto(2), imovie, ntot, frame_counter, nptcls_out
            logical :: l_pick, l_del_forctf, l_skip_pick
            call cline%set('oritype', 'mic')
            call params%new(cline)
            if( params%scale > 1.01 )then
                THROW_HARD('scale cannot be > 1; exec_preprocess')
            endif
            l_pick = .false.
            if( cline%defined('picker') )then
                select case(trim(params%picker))
                case('old')
                    if(.not.cline%defined('pickrefs')) THROW_HARD('PICKREFS required for picker=old')
                case('new')
                    if(cline%defined('pickrefs'))then
                        if( .not. cline%defined('mskdiam') )then
                            THROW_HARD('New picker requires mask diameter (in A) in conjunction with pickrefs')
                        endif
                    else
                        if( .not.cline%defined('moldiam') )then
                            THROW_HARD('MOLDIAM required for picker=new')
                        endif
                    endif
                end select
                l_pick = .true.
            endif
            l_del_forctf = .false.
            ! read in movies
            call spproj%read( params%projfile )
            if( spproj%get_nmovies()==0 .and. spproj%get_nintgs()==0 ) THROW_HARD('No movie/micrograph to process!')
            ! output directories & naming
            output_dir_ctf_estimate        = PATH_HERE
            output_dir_motion_correct      = PATH_HERE
            if( l_pick ) output_dir_picker = PATH_HERE
            if( params%stream.eq.'yes' )then
                output_dir_ctf_estimate   = trim(DIR_CTF_ESTIMATE)
                output_dir_motion_correct = trim(DIR_MOTION_CORRECT)
                if( cline%defined('dir') )then
                    output_dir_ctf_estimate   = filepath(params%dir,output_dir_ctf_estimate)//'/'
                    output_dir_motion_correct = filepath(params%dir,output_dir_motion_correct)//'/'
                endif
                call simple_mkdir(output_dir_ctf_estimate,errmsg="commander_preprocess :: preprocess; ")
                call simple_mkdir(output_dir_motion_correct, errmsg="commander_preprocess :: preprocess;")
                if( l_pick )then
                    output_dir_picker  = trim(DIR_PICKER)
                    output_dir_extract = trim(DIR_EXTRACT)
                    if( cline%defined('dir') )then
                        output_dir_picker  = filepath(params%dir,output_dir_picker)//'/'
                        output_dir_extract = filepath(params%dir,output_dir_extract)//'/'
                    endif
                    call simple_mkdir(output_dir_picker, errmsg="commander_preprocess :: preprocess; ")
                    call simple_mkdir(output_dir_extract, errmsg="commander_preprocess :: preprocess;")
                endif
            endif
            if( cline%defined('fbody') )then
                fbody = trim(params%fbody)
            else
                fbody = ''
            endif
            ! range
            if( trim(params%stream).eq.'yes' )then
                ! STREAMING MODE
                fromto(:) = 1
            else
                ! DISTRIBUTED MODE
                if( cline%defined('fromp') .and. cline%defined('top') )then
                    fromto(1) = params%fromp
                    fromto(2) = params%top
                else
                    THROW_HARD('fromp & top args need to be defined in parallel execution; exec_preprocess')
                endif
            endif
            ntot = fromto(2) - fromto(1) + 1
            ! numlen
            if( cline%defined('numlen') )then
                ! nothing to do
            else
                params%numlen = len(int2str(nmovies))
            endif
            frame_counter = 0
            ! loop over exposures (movies)
            do imovie = fromto(1),fromto(2)
                ! fetch movie orientation
                call spproj%os_mic%get_ori(imovie, o_mov)
                ! sanity check
                if(.not.o_mov%isthere('imgkind') )cycle
                if(.not.o_mov%isthere('movie') .and. .not.o_mov%isthere('intg'))cycle
                call o_mov%getter('imgkind', imgkind)
                select case(trim(imgkind))
                    case('movie')
                        ! motion_correct
                        ctfvars = spproj%get_micparams(imovie)
                        call o_mov%getter('movie', moviename)
                        if( .not.file_exists(moviename)) cycle
                        if( cline%defined('gainref') )then
                            call mciter%iterate(cline, ctfvars, o_mov, fbody, frame_counter, moviename,&
                                &output_dir_motion_correct, gainref_fname=params%gainref)
                        else
                            call mciter%iterate(cline, ctfvars, o_mov, fbody, frame_counter, moviename,&
                                &output_dir_motion_correct)
                        endif
                        moviename_forctf = mciter%get_moviename('forctf')
                        l_del_forctf     = .true.
                    case('mic')
                        ctfvars = spproj%get_micparams(imovie)
                        call o_mov%getter('intg', moviename_forctf)
                    case DEFAULT
                        cycle
                end select
                ! ctf_estimate
                params_glob%hp = params%hp_ctf_estimate
                params_glob%lp = max(params%fny, params%lp_ctf_estimate)
                call ctfiter%iterate(ctfvars, moviename_forctf, o_mov, output_dir_ctf_estimate, .false.)
                ! delete file after estimation
                if( l_del_forctf )then
                    call o_mov%delete_entry('forctf')
                    call del_file(moviename_forctf)
                endif
                ! optional rejection
                l_skip_pick = .false.
                if( trim(params%stream).eq.'yes' )then
                    if( l_pick .and. o_mov%isthere('ctfres') )then
                        l_skip_pick = o_mov%get('ctfres') > (params_glob%ctfresthreshold-0.001)
                        if( l_skip_pick ) call o_mov%set('nptcls',0.)
                    end if
                    ! ! temporarily disabled rejection on icefrac whilst gathering data to determine optimal default cutoff.
                    ! if( l_pick .and. .not. l_skip_pick .and. o_mov%isthere('icefrac') )then
                    !     l_skip_pick = o_mov%get('icefrac') > (params_glob%icefracthreshold-0.001)
                    !     if( l_skip_pick ) call o_mov%set('nptcls',0.)
                    ! endif
                endif
                ! update project
                call spproj%os_mic%set_ori(imovie, o_mov)
                ! pick
                if( l_pick .and. (.not.l_skip_pick) )then
                    smpd_pick      = o_mov%get('smpd')
                    params_glob%lp = max(2.*smpd_pick, params%lp_pick)
                    call o_mov%getter('intg', moviename_intg)
                    call piter%iterate(cline, smpd_pick, moviename_intg, boxfile, nptcls_out, output_dir_picker)
                    call o_mov%set('nptcls',  real(nptcls_out))
                    if( nptcls_out > 0 )then
                        call o_mov%set('boxfile', trim(boxfile))
                    else
                        call o_mov%set('state',0.)
                    endif
                    ! update project
                    call spproj%os_mic%set_ori(imovie, o_mov)
                    ! extract particles
                    if( trim(params%stream) .eq. 'yes' )then
                        ! needs to write and re-read project at the end as extract overwrites it
                        call spproj%write_segment_inside(params%oritype)
                        if( nptcls_out > 0 )then
                            cline_extract = cline
                            call cline_extract%set('smpd',      o_mov%get('smpd')) ! in case of scaling
                            call cline_extract%set('dir',       trim(output_dir_extract))
                            call cline_extract%set('pcontrast', params%pcontrast)
                            call cline_extract%delete('msk')
                            if( cline%defined('box_extract') )call cline_extract%set('box', real(params%box_extract))
                            call xextract%execute(cline_extract)
                            call spproj%kill
                        endif
                    endif
                endif
            end do
            if( trim(params%stream).eq.'yes' )then
                if( (.not.l_pick) .or. l_skip_pick)then
                    ! because extract performs the writing otherwise
                    call spproj%write_segment_inside(params%oritype)
                endif
            else
                call binwrite_oritab(params%outfile, spproj, spproj%os_mic, fromto, isegment=MIC_SEG)
            endif
            call piter%kill
            call o_mov%kill
            ! end gracefully
            call qsys_job_finished(  'simple_commander_preprocess :: exec_preprocess' )
            call simple_end('**** SIMPLE_PREPROCESS NORMAL STOP ****')
        end subroutine exec_preprocess
    
        subroutine exec_motion_correct_distr( self, cline )
            class(motion_correct_commander_distr), intent(inout) :: self
            class(cmdline),                        intent(inout) :: cline
            type(parameters) :: params
            type(sp_project) :: spproj
            type(qsys_env)   :: qenv
            type(chash)      :: job_descr
            if( .not. cline%defined('mkdir')         ) call cline%set('mkdir',       'yes')
            if( .not. cline%defined('trs')           ) call cline%set('trs',           20.)
            if( .not. cline%defined('lpstart')       ) call cline%set('lpstart',        8.)
            if( .not. cline%defined('lpstop')        ) call cline%set('lpstop',         5.)
            if( .not. cline%defined('bfac')          ) call cline%set('bfac',          50.)
            if( .not. cline%defined('groupframes')   ) call cline%set('groupframes',  'no')
            if( .not. cline%defined('mcconvention')  ) call cline%set('mcconvention','simple')
            if( .not. cline%defined('wcrit')         ) call cline%set('wcrit',   'softmax')
            if( .not. cline%defined('eer_upsampling')) call cline%set('eer_upsampling', 1.)
            if( .not. cline%defined('mcpatch')       ) call cline%set('mcpatch',      'yes')
            if( .not. cline%defined('mcpatch_thres'))call cline%set('mcpatch_thres','yes')
            if( .not. cline%defined('algorithm')     ) call cline%set('algorithm', 'patch')
            call cline%set('oritype', 'mic')
            call params%new(cline)
            call cline%set('numlen', real(params%numlen))
            ! sanity check
            call spproj%read_segment(params%oritype, params%projfile)
            if( spproj%get_nmovies() ==0 ) THROW_HARD('no movies to process! exec_motion_correct_distr')
            call spproj%kill
            ! setup the environment for distributed execution
            call qenv%new(params%nparts)
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule & clean
            call qenv%gen_scripts_and_schedule_jobs(job_descr, algnfbody=trim(ALGN_FBODY), array=L_USE_SLURM_ARR)
            ! merge docs
            call spproj%read(params%projfile)
            call spproj%update_projinfo(cline)
            call spproj%write_segment_inside('projinfo')
            call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
            call spproj%kill
            ! clean
            call qsys_cleanup
            ! end gracefully
            call simple_end('**** SIMPLE_DISTR_MOTION_CORRECT NORMAL STOP ****')
        end subroutine exec_motion_correct_distr
    
        subroutine exec_motion_correct( self, cline )
            use simple_sp_project,          only: sp_project
            use simple_motion_correct_iter, only: motion_correct_iter
            class(motion_correct_commander), intent(inout) :: self
            class(cmdline),                  intent(inout) :: cline !< command line input
            type(parameters)              :: params
            type(motion_correct_iter)     :: mciter
            type(ctfparams)               :: ctfvars
            type(sp_project)              :: spproj
            type(ori)                     :: o
            character(len=:), allocatable :: output_dir, moviename, fbody
            integer :: nmovies, fromto(2), imovie, ntot, frame_counter, cnt
            call cline%set('oritype', 'mic')
            call params%new(cline)
            call spproj%read(params%projfile)
            ! sanity check
            nmovies = spproj%get_nmovies()
            if( nmovies == 0 )then
                THROW_HARD('No movie to process!')
            endif
            if( params%scale > 1.01 )then
                THROW_HARD('scale cannot be > 1; exec_motion_correct')
            endif
            if( cline%defined('gainref') )then
                if(.not.file_exists(params%gainref) )then
                    THROW_HARD('gain reference: '//trim(params%gainref)//' not found; motion_correct')
                endif
            endif
            ! output directory & names
            output_dir = PATH_HERE
            if( cline%defined('fbody') )then
                fbody = trim(params%fbody)
            else
                fbody = ''
            endif
            ! determine loop range & fetch movies oris object
            if( cline%defined('fromp') .and. cline%defined('top') )then
                fromto = [params%fromp, params%top]
            else
                THROW_HARD('fromp & top args need to be defined in parallel execution; motion_correct')
            endif
            ntot = fromto(2) - fromto(1) + 1
            ! align
            frame_counter = 0
            cnt = 0
            do imovie=fromto(1),fromto(2)
                call spproj%os_mic%get_ori(imovie, o)
                if( o%isthere('imgkind') )then
                    if( o%isthere('movie') .or. o%isthere('mic') )then
                        cnt = cnt + 1
                        call o%getter('movie', moviename)
                        ctfvars = spproj%get_micparams(imovie)
                        if( cline%defined('gainref') )then
                            call mciter%iterate(cline, ctfvars, o, fbody, frame_counter, moviename, trim(output_dir), gainref_fname=params%gainref)
                        else
                            call mciter%iterate(cline, ctfvars, o, fbody, frame_counter, moviename, trim(output_dir))
                        endif
                        call spproj%os_mic%set_ori(imovie, o)
                        write(logfhandle,'(f4.0,1x,a)') 100.*(real(cnt)/real(ntot)), 'percent of the movies processed'
                    endif
                endif
            end do
            ! output
            call binwrite_oritab(params%outfile, spproj, spproj%os_mic, fromto, isegment=MIC_SEG)
            call o%kill
            ! end gracefully
            call qsys_job_finished(  'simple_commander_preprocess :: exec_motion_correct' )
            call simple_end('**** SIMPLE_MOTION_CORRECT NORMAL STOP ****')
        end subroutine exec_motion_correct
    
        subroutine exec_gen_pspecs_and_thumbs_distr( self, cline )
            class(gen_pspecs_and_thumbs_commander_distr), intent(inout) :: self
            class(cmdline),                               intent(inout) :: cline
            type(parameters) :: params
            type(sp_project) :: spproj
            type(qsys_env)   :: qenv
            type(chash)      :: job_descr
            integer          :: nintgs
            call cline%set('oritype', 'mic')
            if( .not. cline%defined('mkdir') ) call cline%set('mkdir', 'yes')
            call params%new(cline)
            params%numlen = len(int2str(params%nparts))
            call cline%set('numlen', real(params%numlen))
            ! sanity check
            call spproj%read_segment(params%oritype, params%projfile)
            nintgs = spproj%get_nintgs()
            if( nintgs ==0 )then
                THROW_HARD('no integrated movies to process! exec_gen_pspecs_and_thumbs_distr')
            endif
            if( params%nparts > nintgs )then
                call cline%set('nparts', real(nintgs))
                params%nparts = nintgs
            endif
            call spproj%kill
            ! setup the environment for distributed execution
            call qenv%new(params%nparts)
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule & clean
            call qenv%gen_scripts_and_schedule_jobs(job_descr, algnfbody=trim(ALGN_FBODY), array=L_USE_SLURM_ARR)
            ! merge docs
            call spproj%read(params%projfile)
            call spproj%update_projinfo(cline)
            call spproj%segwriter_inside(PROJINFO_SEG)
            call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
            call spproj%kill
            ! clean
            call qsys_cleanup
            ! end gracefully
            call simple_end('**** SIMPLE_DISTR_GEN_PSPECS_AND_THUMBS NORMAL STOP ****')
        end subroutine exec_gen_pspecs_and_thumbs_distr
    
        subroutine exec_gen_pspecs_and_thumbs( self, cline )
            use simple_sp_project,       only: sp_project
            use simple_pspec_thumb_iter, only: pspec_thumb_iter
            class(gen_pspecs_and_thumbs_commander), intent(inout) :: self
            class(cmdline),                         intent(inout) :: cline !< command line input
            type(parameters)              :: params
            type(pspec_thumb_iter)        :: ptiter
            type(sp_project)              :: spproj
            type(ori)                     :: o
            character(len=:), allocatable :: output_dir, moviename_intg, imgkind
            integer :: nintgs, fromto(2), iintg, ntot, cnt
            call cline%set('oritype', 'mic')
            call params%new(cline)
            call spproj%read(params%projfile)
            ! sanity check
            nintgs = spproj%get_nintgs()
            if( nintgs == 0 )then
                THROW_HARD('No integrated movies to process!')
            endif
            ! output directory
            output_dir = PATH_HERE
            ! determine loop range & fetch movies oris object
            if( params%l_distr_exec )then
                if( cline%defined('fromp') .and. cline%defined('top') )then
                    fromto = [params%fromp, params%top]
                else
                    THROW_HARD('fromp & top args need to be defined in parallel execution; gen_pspecs_and_thumbs')
                endif
            else
                fromto = [1,nintgs]
            endif
            ntot = fromto(2) - fromto(1) + 1
            ! align
            cnt = 0
            do iintg=fromto(1),fromto(2)
                call spproj%os_mic%get_ori(iintg, o)
                if( o%isthere('imgkind').and.o%isthere('intg') )then
                    cnt = cnt + 1
                    call o%getter('imgkind', imgkind)
                    if( imgkind.ne.'mic' )cycle
                    call o%getter('intg', moviename_intg)
                    call ptiter%iterate(o, moviename_intg, trim(output_dir))
                    call spproj%os_mic%set_ori(iintg, o)
                    write(logfhandle,'(f4.0,1x,a)') 100.*(real(cnt)/real(ntot)), 'percent of the integrated movies processed'
                endif
            end do
            ! output
            call binwrite_oritab(params%outfile, spproj, spproj%os_mic, fromto, isegment=MIC_SEG)
            call o%kill
            ! end gracefully
            call qsys_job_finished('simple_commander_preprocess :: exec_gen_pspecs_and_thumbs')
            call simple_end('**** SIMPLE_GEN_PSPECS_AND_THUMBS NORMAL STOP ****')
        end subroutine exec_gen_pspecs_and_thumbs
    
        subroutine exec_ctf_estimate_distr( self, cline )
            class(ctf_estimate_commander_distr), intent(inout) :: self
            class(cmdline),                      intent(inout) :: cline
            type(parameters)              :: params
            type(sp_project)              :: spproj
            type(chash)                   :: job_descr
            type(qsys_env)                :: qenv
            if( .not. cline%defined('mkdir')   ) call cline%set('mkdir',  'yes')
            if( .not. cline%defined('pspecsz') ) call cline%set('pspecsz', 512.)
            if( .not. cline%defined('hp')      ) call cline%set('hp',       30.)
            if( .not. cline%defined('lp')      ) call cline%set('lp',        5.)
            if( .not. cline%defined('dfmin')   ) call cline%set('dfmin',    DFMIN_DEFAULT)
            if( .not. cline%defined('dfmax')   ) call cline%set('dfmax',    DFMAX_DEFAULT)
            if( .not. cline%defined('oritype') ) call cline%set('oritype','mic')
            if( .not. cline%defined('ctfpatch')) call cline%set('ctfpatch','yes')
            call params%new(cline)
            ! sanity check
            call spproj%read_segment(params%oritype, params%projfile)
            if( spproj%get_nintgs() ==0 )then
                THROW_HARD('no micrograph to process! exec_ctf_estimate_distr')
            endif
            call spproj%kill
            ! set mkdir to no (to avoid nested directory structure)
            call cline%set('mkdir', 'no')
            params%numlen = len(int2str(params%nparts))
            call cline%set('numlen', real(params%numlen))
            ! setup the environment for distributed execution
            call qenv%new(params%nparts)
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule
            call qenv%gen_scripts_and_schedule_jobs( job_descr, algnfbody=trim(ALGN_FBODY), array=L_USE_SLURM_ARR)
            ! merge docs
            call spproj%read(params%projfile)
            call spproj%update_projinfo(cline)
            call spproj%write_segment_inside('projinfo')
            call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
            ! cleanup
            call spproj%kill
            call qsys_cleanup
            ! graceful ending
            call simple_end('**** SIMPLE_DISTR_CTF_ESTIMATE NORMAL STOP ****')
        end subroutine exec_ctf_estimate_distr
    
        subroutine exec_ctf_estimate( self, cline )
            use simple_sp_project,          only: sp_project
            use simple_ctf_estimate_iter,   only: ctf_estimate_iter
            class(ctf_estimate_commander), intent(inout) :: self
            class(cmdline),                intent(inout) :: cline  !< command line input
            type(parameters)              :: params
            type(sp_project)              :: spproj
            type(ctf_estimate_iter)       :: ctfiter
            type(ctfparams)               :: ctfvars
            type(ori)                     :: o
            character(len=:), allocatable :: intg_forctf, output_dir, imgkind
            integer                       :: fromto(2), imic, ntot, cnt, state
            logical                       :: l_gen_thumb, l_del_forctf
            call cline%set('oritype', 'mic')
            call params%new(cline)
            call spproj%read(params%projfile)
            ! read in integrated movies
            if( spproj%get_nintgs() == 0 ) THROW_HARD('No integrated micrograph to process!')
            ! output directory
            output_dir = PATH_HERE
            ! parameters & loop range
            if( params%stream .eq. 'yes' )then
                ! determine loop range
                fromto(:) = 1
            else
                if( cline%defined('fromp') .and. cline%defined('top') )then
                    fromto(1) = params%fromp
                    fromto(2) = params%top
                else
                    THROW_HARD('fromp & top args need to be defined in parallel execution; exec_ctf_estimate')
                endif
            endif
            ntot = fromto(2) - fromto(1) + 1
            ! loop over exposures (movies)
            cnt = 0
            do imic = fromto(1),fromto(2)
                cnt   = cnt + 1
                call spproj%os_mic%get_ori(imic, o)
                state = 1
                if( o%isthere('state') ) state = nint(o%get('state'))
                if( state == 0 ) cycle
                if( o%isthere('imgkind') )then
                    call o%getter('imgkind', imgkind)
                    if( imgkind.ne.'mic' )cycle
                    l_del_forctf = .false.
                    if( o%isthere('forctf') )then
                        call o%getter('forctf', intg_forctf)
                        if( file_exists(intg_forctf) )then
                            l_del_forctf = .true.
                        else
                            if( o%isthere('intg') )then
                                call o%getter('intg', intg_forctf)
                            endif
                        endif
                    else if( o%isthere('intg') )then
                        call o%getter('intg', intg_forctf)
                    else
                        THROW_HARD('no image available (forctf|intg) for CTF fittings :: exec_ctf_estimate')
                    endif
                    l_gen_thumb = .not. o%isthere('thumb')
                    ctfvars     = o%get_ctfvars()
                    call ctfiter%iterate( ctfvars, intg_forctf, o, trim(output_dir), l_gen_thumb)
                    ! delete file after estimation
                    if( l_del_forctf )then
                        call o%delete_entry('forctf')
                        call del_file(intg_forctf)
                    endif
                    ! update project
                    call spproj%os_mic%set_ori(imic, o)
                endif
                write(logfhandle,'(f4.0,1x,a)') 100.*(real(cnt)/real(ntot)), 'percent of the micrographs processed'
            end do
            ! output
            call binwrite_oritab(params%outfile, spproj, spproj%os_mic, fromto, isegment=MIC_SEG)
            call o%kill
            ! end gracefully
            call qsys_job_finished(  'simple_commander_preprocess :: exec_ctf_estimate' )
            call simple_end('**** SIMPLE_CTF_ESTIMATE NORMAL STOP ****')
        end subroutine exec_ctf_estimate
    
        subroutine exec_map_cavgs_selection( self, cline )
            use simple_corrmat,             only: calc_cartesian_corrmat
            class(map_cavgs_selection_commander), intent(inout) :: self
            class(cmdline),                       intent(inout) :: cline
            type(parameters)              :: params
            type(builder)                 :: build
            type(image),      allocatable :: imgs_sel(:), imgs_all(:)
            integer,          allocatable :: states(:)
            real,             allocatable :: correlations(:,:)
            character(len=:), allocatable :: cavgstk
            integer :: iimg, isel, nall, nsel, loc(1), lfoo(3)
            real    :: smpd
            call cline%set('dir_exec', 'selection')
            call cline%set('mkdir',    'yes')
            if( .not.cline%defined('prune') ) call cline%set('prune', 'no')
            call build%init_params_and_build_spproj(cline,params)
            call build%spproj%update_projinfo(cline)
            ! find number of selected cavgs
            call find_ldim_nptcls(params%stk2, lfoo, nsel)
            if( cline%defined('ares') ) nsel = int(params%ares)
            ! find number of original cavgs
            if( .not. cline%defined('stk' ) )then
                call build%spproj%get_cavgs_stk(cavgstk, nall, smpd)
                params%stk = trim(cavgstk)
            else
                call find_ldim_nptcls(params%stk, lfoo, nall)
            endif
            ! read images
            allocate(imgs_sel(nsel), imgs_all(nall))
            do isel=1,nsel
                call imgs_sel(isel)%new([params%box,params%box,1], params%smpd)
                call imgs_sel(isel)%read(params%stk2, isel)
            end do
            do iimg=1,nall
                call imgs_all(iimg)%new([params%box,params%box,1], params%smpd)
                call imgs_all(iimg)%read(params%stk, iimg)
            end do
            write(logfhandle,'(a)') '>>> CALCULATING CORRELATIONS'
            call calc_cartesian_corrmat(imgs_sel, imgs_all, correlations)
            ! create the states array for mapping the selection
            allocate(states(nall), source=0)
            do isel=1,nsel
                loc = maxloc(correlations(isel,:))
                states(loc(1)) = 1
            end do
            ! communicate selection to project
            call build%spproj%map_cavgs_selection(states)
            ! optional pruning
            if( trim(params%prune).eq.'yes') call build%spproj%prune_particles
            ! this needs to be a full write as many segments are updated
            call build%spproj%write
            ! end gracefully
            call simple_end('**** SIMPLE_MAP_CAVGS_SELECTION NORMAL STOP ****')
        end subroutine exec_map_cavgs_selection
    
        subroutine exec_map_cavgs_states( self, cline )
            use simple_corrmat, only: calc_cartesian_corrmat
            class(map_cavgs_states_commander), intent(inout) :: self
            class(cmdline),                    intent(inout) :: cline !< command line input
            type(parameters)                   :: params
            type(builder)                      :: build
            type(image),           allocatable :: imgs_sel(:), imgs_all(:)
            integer,               allocatable :: states(:)
            real,                  allocatable :: correlations(:,:)
            character(len=:),      allocatable :: cavgstk, fname
            character(LONGSTRLEN), allocatable :: stkfnames(:)
            integer :: iimg, isel, nall, nsel, loc(1), lfoo(3), s
            real    :: smpd
            call cline%set('dir_exec', 'state_mapping')
            call cline%set('mkdir',    'yes')
            call build%init_params_and_build_spproj(cline,params)
            call build%spproj%update_projinfo(cline)
            call read_filetable(params%stktab, stkfnames)
            ! find number of original cavgs
            if( .not. cline%defined('stk' ) )then
                call build%spproj%get_cavgs_stk(cavgstk, nall, smpd)
                params%stk = trim(cavgstk)
            else
                call find_ldim_nptcls(params%stk, lfoo, nall)
            endif
            ! read images
            allocate(imgs_all(nall))
            do iimg=1,nall
                call imgs_all(iimg)%new([params%box,params%box,1], params%smpd)
                call imgs_all(iimg)%read(params%stk, iimg)
            end do
            ! create the states array for mapping the selection
            allocate(states(nall), source=0)
            do s = 1,size(stkfnames)
                ! find number of selected cavgs
                fname = '../'//trim(stkfnames(s))
                call find_ldim_nptcls(fname, lfoo, nsel)
                ! read images
                allocate(imgs_sel(nsel))
                do isel=1,nsel
                    call imgs_sel(isel)%new([params%box,params%box,1], params%smpd)
                    call imgs_sel(isel)%read(fname, isel)
                end do
                call calc_cartesian_corrmat(imgs_sel, imgs_all, correlations)
                do isel=1,nsel
                    loc = maxloc(correlations(isel,:))
                    states(loc(1)) = s
                end do
                ! destruct
                do isel=1,nsel
                    call imgs_sel(isel)%kill
                end do
                deallocate(imgs_sel)
            end do
            ! communicate selection to project
            call build%spproj%map_cavgs_selection(states)
            ! this needs to be a full write as many segments are updated
            call build%spproj%write
            ! end gracefully
            call simple_end('**** SIMPLE_MAP_CAVGS_SELECTION NORMAL STOP ****')
        end subroutine exec_map_cavgs_states
    
        subroutine exec_pick_distr( self, cline )
            use simple_strings
            use simple_math
            class(pick_commander_distr), intent(inout) :: self
            class(cmdline),              intent(inout) :: cline
            type(parameters) :: params
            type(sp_project) :: spproj
            type(cmdline)    :: cline_make_pickrefs
            type(qsys_env)   :: qenv
            type(chash)      :: job_descr
            logical :: templates_provided
            
            ! added 11/6, will move to separate subroutine once it works
            real, allocatable :: mic_stats(:,:) 
            real, allocatable :: avg_stats(:,:)
            real, allocatable :: all_stats(:,:,:)
            real, allocatable :: max_smds(:,:)
            real, allocatable :: max_ksstats(:,:)
            real, allocatable :: max_a_peaks(:,:)
            integer :: nmoldiams, nmicrographs, imic, idiam, idiam_2, iapeak, ismd, iksstat
            !character(len=4) :: idiam_str
    
            if( .not. cline%defined('mkdir')     ) call cline%set('mkdir',       'yes')
            if( .not. cline%defined('pcontrast') ) call cline%set('pcontrast', 'black')
            if( .not. cline%defined('oritype')   ) call cline%set('oritype',     'mic')
            if( .not. cline%defined('ndev')      ) call cline%set('ndev',           2.)
            if( .not. cline%defined('thres')     ) call cline%set('thres',         24.)
            call params%new(cline)
            ! sanity check
            call spproj%read_segment(params%oritype, params%projfile)
            if( spproj%get_nintgs() ==0 ) THROW_HARD('No micrograph to process! exec_pick_distr')
            call spproj%kill
            ! set mkdir to no (to avoid nested directory structure)
            call cline%set('mkdir', 'no')
            params%numlen = len(int2str(params%nparts))
            call cline%set('numlen', real(params%numlen))
            ! more sanity checks
            templates_provided = cline%defined('pickrefs')
            if( .not.templates_provided )then
                if( .not.cline%defined('moldiam') ) THROW_HARD('Need molecular diameter in A (moldiam) as input for reference-free pick')
            endif
            select case(trim(params%picker))
                case('old')
                    if( .not. cline%defined('pickrefs') ) THROW_HARD('Old picker requires pickrefs (2D picking references) input')
                case('new')
                    if( cline%defined('pickrefs') )then
                        if( .not. cline%defined('mskdiam') ) THROW_HARD('New picker requires mask diameter (in A) in conjunction with pickrefs')
                    else if( cline%defined('moldiam') )then
                        ! at least moldiam is required
                    else
                        THROW_HARD('New picker requires 2D references (pickrefs) or moldiam')
                    endif
            end select
            ! setup the environment for distributed execution
            call qenv%new(params%nparts)
            select case(trim(params%picker))
                case('old')
                    ! prepares picking references
                    cline_make_pickrefs = cline
                    if( templates_provided )then
                        call cline_make_pickrefs%set('prg','make_pickrefs')
                        call qenv%exec_simple_prg_in_queue(cline_make_pickrefs, 'MAKE_PICKREFS_FINISHED')
                        call cline%set('pickrefs', trim(PICKREFS)//params%ext)
                        write(logfhandle,'(A)')'>>> PREPARED PICKING TEMPLATES'
                    endif
            end select
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule & clean
            call qenv%gen_scripts_and_schedule_jobs(job_descr, algnfbody=trim(ALGN_FBODY), array=L_USE_SLURM_ARR)
            ! merge docs
            call spproj%read(params%projfile)
            call spproj%update_projinfo(cline)
            call spproj%write_segment_inside('projinfo')
            call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
            call spproj%write_segment2txt('mic','spproj_mic.txt')
            print *, "params nptcls",params%nptcls
            
            nmoldiams = params%nmoldiams
            nmicrographs = spproj%os_mic%get_noris()
    
            allocate(mic_stats(nmoldiams,4))
            allocate(all_stats(nmicrographs,nmoldiams,4))
            allocate(avg_stats(nmoldiams,4))
    
            ! may want to make this into its own subroutine
            do imic = 1, nmicrographs 
                do idiam = 1, nmoldiams
                    mic_stats(idiam,1) = spproj%os_mic%get(imic,'moldiam_'//int2str(idiam))
                    mic_stats(idiam,2) = spproj%os_mic%get(imic,'smd_'//int2str(idiam))
                    mic_stats(idiam,3) = spproj%os_mic%get(imic,'ksstat_'//int2str(idiam))
                    mic_stats(idiam,4) = spproj%os_mic%get(imic,'a_peak_'//int2str(idiam))
                end do 
                all_stats(imic,:,:) = mic_stats
            end do
            
            ! csv to save picker data
            open(unit=1, file='stats.csv', status='unknown')
            write(1, '(7(a,1x))') 'moldiam', ',', 'smd', ',', 'ksstat', ',', 'a_peak'
            do idiam_2 = 1, nmoldiams
                avg_stats(idiam_2,1) = all_stats(1,idiam_2,1)
                avg_stats(idiam_2,2) = sum(all_stats(:,idiam_2,2))/size(all_stats(:,idiam_2,2))
                avg_stats(idiam_2,3) = sum(all_stats(:,idiam_2,3))/size(all_stats(:,idiam_2,3))
                avg_stats(idiam_2,4) = sum(all_stats(:,idiam_2,4))/size(all_stats(:,idiam_2,4))
                write(1, '(4(f7.3,a))') avg_stats(idiam_2,1), ',', avg_stats(idiam_2,2), ',', avg_stats(idiam_2,3), ',', avg_stats(idiam_2,4)
            end do
            close(1)
    
            ! find peak values
            ! I thought a function to do this existed somewhere in the code but I cannot find it
            max_smds = find_local_maxima(avg_stats(:,1),avg_stats(:,2),nmoldiams)
            max_ksstats = find_local_maxima(avg_stats(:,1),avg_stats(:,3),nmoldiams)
            max_a_peaks = find_local_maxima(avg_stats(:,1),avg_stats(:,4),nmoldiams)
    
            do ismd=1, size(max_smds(:,1))
                print *, 'Local max smd of ', max_smds(ismd,2), ' occurs at moldiam ', max_smds(ismd,1)
            end do
    
            do iksstat=1, size(max_ksstats(:,1))
                print *, 'Local max ksstat of ', max_ksstats(iksstat,2), ' occurs at moldiam ', max_ksstats(iksstat,1)
            end do
    
            do iapeak=1, size(max_a_peaks(:,1))
                print *, 'Local max a_peak of ', max_a_peaks(iapeak,2), ' occurs at moldiam ', max_a_peaks(iapeak,1)
            end do 
        
            ! deallocate arrays created to process picker statistics
            deallocate(mic_stats)
            deallocate(all_stats)
            deallocate(avg_stats)
    
            !! not sure about these, created in function find_local_maxima in simple_math
            deallocate(max_smds)
            deallocate(max_ksstats)
            deallocate(max_a_peaks)
            
            ! cleanup
            call qsys_cleanup
            ! graceful exit
            call simple_end('**** ****')
        end subroutine exec_pick_distr
    
        subroutine exec_pick( self, cline )
            use simple_picker_iter, only: picker_iter
            use simple_strings, only: real2str, int2str
            class(pick_commander), intent(inout) :: self
            class(cmdline),        intent(inout) :: cline !< command line input
            type(parameters)              :: params
            type(sp_project)              :: spproj
            type(picker_iter)             :: piter
            type(ori)                     :: o
            character(len=:), allocatable :: output_dir, intg_name, imgkind
            character(len=LONGSTRLEN)     :: boxfile 
            integer                       :: fromto(2), imic, ntot, nptcls_out, cnt, state, idiam, i
            real, allocatable             :: mic_stats(:,:)
            real                          :: fromto_diam(2)
            real, allocatable             :: avg_picker_stats(:,:)
    
            call cline%set('oritype', 'mic')
            call params%new(cline)
            
            ! output directory
            output_dir = PATH_HERE
            ! parameters & loop range
            if( params%stream .eq. 'yes' )then
                ! determine loop range
                fromto(:) = 1
            else
                if( cline%defined('fromp') .and. cline%defined('top') )then
                    fromto(1) = params%fromp
                    fromto(2) = params%top
                else
                    THROW_HARD('fromp & top args need to be defined in parallel execution; exec_pick')
                endif
            endif
            ntot = fromto(2) - fromto(1) + 1 !number micrographs
            print *, "ntot total micrographs", ntot, fromto(2), fromto(1)
            ! read project file
            call spproj%read(params%projfile)
            ! look for movies
            if( spproj%get_nintgs() == 0 )then
                THROW_HARD('No integrated micrograph to process!')
            endif
    
            if (cline%defined('moldiam_up')) then
                fromto_diam=[params%moldiam, params%moldiam_up]
            else if(.not. cline%defined('multipick') .or. params%multipick .eq. 'no' .or. params%nmoldiams .eq. 1) then
                fromto_diam=[params%moldiam,params%moldiam]
            else
                fromto_diam=[params%moldiam-50,params%moldiam+50]
            endif
    
            cnt = 0
            
            do imic=fromto(1),fromto(2)
                allocate(mic_stats(params%nmoldiams,4))
                cnt = cnt + 1
                call spproj%os_mic%get_ori(imic, o)
                state = 1
                if( o%isthere('state') ) state = nint(o%get('state'))
                if( state == 0 ) cycle
                if( o%isthere('imgkind') )then
                    call o%getter('imgkind', imgkind)
                    if( imgkind.ne.'mic' )cycle
                    call o%getter('intg', intg_name)
                    call piter%iterate(cline=cline, smpd=params%smpd, moviename_intg=intg_name, boxfile=boxfile, nptcls_out=nptcls_out, dir_out=output_dir, mic_stats=mic_stats(:,:), fromto_diam=fromto_diam, nmoldiams=params%nmoldiams ) ! should populate picker_stats with 2d arrays of pick stat for each mic
                    call spproj%os_mic%set_boxfile(imic, boxfile, nptcls=nptcls_out)
                    do idiam=1,params%nmoldiams
                        call spproj%os_mic%set(imic,'moldiam_'//int2str(idiam),mic_stats(idiam,1))
                        call spproj%os_mic%set(imic,'smd_'//int2str(idiam),mic_stats(idiam,2))
                        call spproj%os_mic%set(imic,'ksstat_'//int2str(idiam),mic_stats(idiam,3))
                        call spproj%os_mic%set(imic,'a_peak_'//int2str(idiam),mic_stats(idiam,4))
                    end do
                    call spproj%os_mic%set(imic,'nmoldiams',real(params%nmoldiams))
                endif
                deallocate(mic_stats)
            write(logfhandle,'(f4.0,1x,a)') 100.*(real(cnt)/(real(ntot))), 'percent of the micrographs processed'
                
            end do
            
            ! output
            call binwrite_oritab(params%outfile, spproj, spproj%os_mic, fromto, isegment=MIC_SEG)
    
            ! cleanup
            call o%kill
            call spproj%kill
            call piter%kill
            close(unit=1)
    
            ! end gracefully
            call qsys_job_finished( 'simple_commander_preprocess :: exec_pick' )
            call simple_end('**** SIMPLE_PICK NORMAL STOP ****')
        end subroutine exec_pick
    
        ! new multipick
        subroutine exec_multipick(self, cline)
            use simple_strings
            class(multipick_commander), intent(inout) :: self
            class(cmdline),             intent(inout) :: cline
            !type(sp_project) :: spproj
            !type(parameters) :: params
            !integer :: imic, idiam, nmoldiams, nargs, idiam_2, nmicrographs
            !character(len=LONGSTRLEN) :: temp_stats_str
            !character(len=20) :: args(4) 
            !character(len=30) :: keyname
            !real, allocatable :: mic_stats(:,:), all_stats(:,:,:), avg_stats(:,:)
            
    
            !print *, "ENTERING MULTIPICK"
            !call params%new(cline)
            !call spproj%read(params%projfile)
            
            !nmoldiams = int(spproj%os_mic%get(1,'nmoldiams'))
            !nmicrographs = spproj%os_mic%get_noris()
    
            !allocate(mic_stats(nmoldiams,4))
            !allocate(all_stats(nmicrographs,nmoldiams,4))
            !allocate(avg_stats(nmoldiams,4))
    
            !do imic = 1, nmicrographs 
            !    do idiam = 1, nmoldiams
            !        keyname='Stats_moldiam_'//real2str(real(idiam))
            !        temp_stats_str = spproj%os_mic%get(imic,keyname) 
            !        ! split string and insert into array
            !       call parsestr(temp_stats_str,delim=',',args=args,nargs=nargs)
            !        mic_stats(idiam,1) = str2real(args(1))
            !        mic_stats(idiam,2) = str2real(args(2))
            !        mic_stats(idiam,3) = str2real(args(3))
            !        mic_stats(idiam,4) = str2real(args(4))
            !    end do 
            !    all_stats(imic,:,:) = mic_stats
            !end do
            
            !do idiam_2 = 1, nmoldiams
            !    avg_stats(idiam_2,1) = all_stats(1,idiam_2,1)
            !    avg_stats(idiam_2,2) = sum(all_stats(:,idiam_2,2))/size(all_stats(:,idiam_2,2))
            !    avg_stats(idiam_2,3) = sum(all_stats(:,idiam_2,3))/size(all_stats(:,idiam_2,3))
            !    avg_stats(idiam_2,4) = sum(all_stats(:,idiam_2,4))/size(all_stats(:,idiam_2,4))
            !end do
           
            
        end subroutine
    
        subroutine exec_extract_distr( self, cline )
            class(extract_commander_distr), intent(inout) :: self
            class(cmdline),           intent(inout) :: cline !< command line input
            type(parameters)                        :: params
            type(sp_project)                        :: spproj, spproj_part
            type(qsys_env)                          :: qenv
            type(chash)                             :: job_descr
            type(ori)                               :: o_mic, o_tmp
            type(oris)                              :: os_stk
            character(len=LONGSTRLEN),  allocatable :: boxfiles(:), stktab(:), parts_fname(:)
            character(len=:),           allocatable :: mic_name, imgkind, boxfile_name
            real    :: dfx,dfy,ogid,gid
            integer :: boxcoords(2), lfoo(3)
            integer :: nframes,imic,i,nmics_tot,numlen,nmics,cnt,state,istk,nstks,ipart
            if( .not. cline%defined('mkdir')         ) call cline%set('mkdir',          'yes')
            if( .not. cline%defined('outside')       ) call cline%set('outside',         'no')
            if( .not. cline%defined('pcontrast')     ) call cline%set('pcontrast',    'black')
            if( .not. cline%defined('stream')        ) call cline%set('stream',          'no')
            if( .not. cline%defined('extractfrommov')) call cline%set('extractfrommov',  'no')
            if( cline%defined('ctf') )then
                if( cline%get_carg('ctf').ne.'flip' .and. cline%get_carg('ctf').ne.'no' )then
                    THROW_HARD('Only CTF=NO/FLIP are allowed')
                endif
            endif
            call cline%set('oritype', 'mic')
            call params%new(cline)
            call cline%set('mkdir', 'no')
            ! read in integrated movies
            call spproj%read(params%projfile)
            call spproj%update_projinfo(cline)
            if( spproj%get_nintgs() == 0 ) THROW_HARD('No integrated micrograph to process!')
            nmics_tot = spproj%os_mic%get_noris()
            if( nmics_tot < params%nparts ) params%nparts = nmics_tot
            ! wipes previous stacks & particles
            call spproj%os_stk%kill
            call spproj%os_ptcl2D%kill
            call spproj%os_ptcl3D%kill
            call spproj%os_cls2D%kill
            call spproj%os_cls3D%kill
            call spproj%os_out%kill
            ! input directory
            if( cline%defined('dir_box') )then
                if( params%mkdir.eq.'yes' .and. params%dir_box(1:1).ne.'/')then
                    params%dir_box = trim(filepath(PATH_PARENT,params%dir_box))
                endif
                params%dir_box = simple_abspath(params%dir_box)
                if( file_exists(params%dir_box) )then
                    call simple_list_files_regexp(params%dir_box,'\.box$', boxfiles)
                    if(.not.allocated(boxfiles))then
                        write(logfhandle,*)'No box file found in ', trim(params%dir_box), '; simple_commander_preprocess::exec_extract 1'
                        THROW_HARD('No box file found; exec_extract, 1')
                    endif
                    if(size(boxfiles)==0)then
                        write(logfhandle,*)'No box file found in ', trim(params%dir_box), '; simple_commander_preprocess::exec_extract 2'
                        THROW_HARD('No box file found; exec_extract 2')
                    endif
                else
                    write(logfhandle,*)'Directory does not exist: ', trim(params%dir_box), 'simple_commander_preprocess::exec_extract'
                    THROW_HARD('box directory does not exist; exec_extract')
                endif
                call cline%set('dir_box', params%dir_box)
            endif
            call spproj%write(params%projfile)
            ! sanity checks
            nmics  = 0
            do imic = 1, nmics_tot
                call spproj%os_mic%get_ori(imic, o_mic)
                state = 1
                if( o_mic%isthere('state') ) state = nint(o_mic%get('state'))
                if( state == 0 ) cycle
                if( .not. o_mic%isthere('imgkind') )cycle
                if( .not. o_mic%isthere('intg')    )cycle
                call o_mic%getter('imgkind', imgkind)
                if( trim(imgkind).ne.'mic') cycle
                call o_mic%getter('intg', mic_name)
                if( .not.file_exists(mic_name) )cycle
                ! box input
                if( cline%defined('dir_box') )then
                    boxfile_name = boxfile_from_mic(mic_name)
                    if(trim(boxfile_name).eq.NIL)cycle
                else
                    call o_mic%getter('boxfile', boxfile_name)
                    if( .not.file_exists(boxfile_name) )cycle
                endif
                ! get number of frames from stack
                call find_ldim_nptcls(mic_name, lfoo, nframes )
                if( nframes > 1 ) THROW_HARD('multi-frame extraction not supported; exec_extract')
                ! update counter
                nmics = nmics + 1
            enddo
            if( nmics == 0 ) THROW_HARD('No particles to extract! exec_extract')
            ! progress
            call progressfile_init_parts(params%nparts) 
            ! DISTRIBUTED EXTRACTION
            ! setup the environment for distributed execution
            call qenv%new(params%nparts)
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule & clean
            call qenv%gen_scripts_and_schedule_jobs( job_descr, algnfbody=trim(ALGN_FBODY), array=L_USE_SLURM_ARR)
            ! ASSEMBLY
            allocate(parts_fname(params%nparts))
            numlen = len(int2str(params%nparts))
            do ipart = 1,params%nparts
                parts_fname(ipart) = trim(ALGN_FBODY)//int2str_pad(ipart,numlen)//trim(METADATA_EXT)
            enddo
            ! copy updated micrographs
            cnt   = 0
            nstks = 0
            do ipart = 1,params%nparts
                call spproj_part%read_segment('mic',parts_fname(ipart))
                do imic = 1,spproj_part%os_mic%get_noris()
                    cnt = cnt + 1
                    call spproj_part%os_mic%get_ori(imic, o_mic)
                    call spproj%os_mic%set_ori(cnt,o_mic)
                    if( o_mic%isthere('nptcls') )then
                        if( nint(o_mic%get('nptcls')) > 0 ) nstks = nstks + 1
                    endif
                enddo
                call spproj_part%kill
            enddo
            if( cnt /= nmics_tot ) THROW_HARD('Inconstistent number of micrographs in individual projects')
            ! fetch stacks table
            if( nstks > 0 )then
                call os_stk%new(nstks, is_ptcl=.false.)
                allocate(stktab(nstks))
                cnt = 0
                do ipart = 1,params%nparts
                    call spproj_part%read_segment('stk',parts_fname(ipart))
                    do istk = 1,spproj_part%os_stk%get_noris()
                        cnt = cnt + 1
                        call spproj_part%os_stk%get_ori(istk, o_tmp)
                        call os_stk%set_ori(cnt,o_tmp)
                        stktab(cnt) = os_stk%get_static(cnt,'stk')
                    enddo
                    call spproj_part%kill
                enddo
                ! import stacks into project
                call spproj%add_stktab(stktab,os_stk)
                ! transfer particles locations to ptcl2D & defocus to 2D/3D
                cnt = 0
                do ipart = 1,params%nparts
                    call spproj_part%read_segment('ptcl2D',parts_fname(ipart))
                    do i = 1,spproj_part%os_ptcl2D%get_noris()
                        cnt = cnt + 1
                        ! picking coordinates
                        call spproj_part%get_boxcoords(i, boxcoords)
                        call spproj%set_boxcoords(cnt, boxcoords)
                        ! defocus from patch-based ctf estimation
                        if( spproj_part%os_ptcl2D%isthere(i,'dfx') )then
                            dfx = spproj_part%os_ptcl2D%get_dfx(i)
                            dfy = spproj_part%os_ptcl2D%get_dfy(i)
                            call spproj%os_ptcl2D%set_dfx(cnt,dfx)
                            call spproj%os_ptcl2D%set_dfy(cnt,dfy)
                            call spproj%os_ptcl3D%set_dfx(cnt,dfx)
                            call spproj%os_ptcl3D%set_dfy(cnt,dfy)
                        endif
                        !optics group id
                        if( spproj_part%os_ptcl2D%isthere(i,'ogid') )then
                            ogid = spproj_part%os_ptcl2D%get(i, 'ogid')
                            call spproj%os_ptcl2D%set(cnt,'ogid',ogid)
                            call spproj%os_ptcl3D%set(cnt,'ogid',ogid)
                        endif
                        !group id
                        if( spproj_part%os_ptcl2D%isthere(i,'gid') )then
                            gid = spproj_part%os_ptcl2D%get(i, 'gid')
                            call spproj%os_ptcl2D%set(cnt,'gid',gid)
                            call spproj%os_ptcl3D%set(cnt,'gid',gid)
                        endif
                    enddo
                    call spproj_part%kill
                enddo
                call os_stk%kill
            endif
            ! final write
            call spproj%write(params%projfile)
            ! progress
            call progressfile_complete_parts(params%nparts) 
            ! clean
            call spproj%kill
            call o_mic%kill
            call o_tmp%kill
            call qsys_cleanup
            ! end gracefully
            call simple_end('**** SIMPLE_EXTRACT_DISTR NORMAL STOP ****')
    
            contains
    
                character(len=LONGSTRLEN) function boxfile_from_mic(mic)
                    character(len=*), intent(in) :: mic
                    character(len=LONGSTRLEN)    :: box_from_mic
                    integer :: ibox
                    box_from_mic     = fname_new_ext(basename(mic),'box')
                    boxfile_from_mic = NIL
                    do ibox=1,size(boxfiles)
                        if(trim(basename(boxfiles(ibox))).eq.trim(box_from_mic))then
                            boxfile_from_mic = trim(boxfiles(ibox))
                            return
                        endif
                    enddo
                end function boxfile_from_mic
    
        end subroutine exec_extract_distr
    
        subroutine exec_extract( self, cline )
            use simple_ctf,                 only: ctf
            use simple_ctf_estimate_fit,    only: ctf_estimate_fit
            use simple_strategy2D3D_common, only: prepimgbatch, killimgbatch
            use simple_particle_extractor,  only: ptcl_extractor
            class(extract_commander), intent(inout) :: self
            class(cmdline),           intent(inout) :: cline !< command line input
            type(builder)                           :: build
            type(parameters)                        :: params
            type(ptcl_extractor)                    :: extractor
            type(sp_project)                        :: spproj_in, spproj
            type(nrtxtfile)                         :: boxfile
            type(image)                             :: micrograph
            type(ori)                               :: o_mic, o_tmp
            type(ctf)                               :: tfun
            type(ctfparams)                         :: ctfparms
            type(ctf_estimate_fit)                  :: ctffit
            type(stack_io)                          :: stkio_w
            character(len=:),           allocatable :: output_dir, mic_name, imgkind
            real,                       allocatable :: boxdata(:,:)
            integer,                    allocatable :: ptcl_inds(:)
            logical,                    allocatable :: oris_mask(:), mics_mask(:)
            character(len=LONGSTRLEN) :: stack, boxfile_name, box_fname, ctfdoc
            character(len=STDLEN)     :: ext
            real                      :: ptcl_pos(2), stk_mean,stk_sdev,stk_max,stk_min,dfx,dfy,prog
            integer                   :: ldim(3), lfoo(3), fromto(2)
            integer                   :: nframes, imic, iptcl, nptcls,nmics,nmics_here,box, box_first, i, iptcl_g
            integer                   :: cnt, nmics_tot, ifoo, state, iptcl_glob, nptcls2extract
            logical                   :: l_ctfpatch, l_gid_present, l_ogid_present,prog_write,prog_part
            call cline%set('oritype', 'mic')
            call cline%set('mkdir',   'no')
            call params%new(cline)
            ! init
            output_dir = PATH_HERE
            fromto(:)  = [params%fromp, params%top]
            nmics_here = fromto(2)-fromto(1)+1
            prog_write = .false.
            prog_part  = .false.
            if( params%stream.eq.'yes' )then
                output_dir = DIR_EXTRACT
                if( cline%defined('dir') ) output_dir = trim(params%dir)//'/'
                fromto(:)  = [1,1]
                nmics_here = 1
                ! read in integrated movies, output project = input project
                call spproj%read(params%projfile)
                nmics_tot = spproj_in%os_mic%get_noris()
                if( spproj%get_nintgs() /= 1 ) THROW_HARD('Incompatible # of integrated micrograph to process!')
            else
                ! read in integrated movies
                call spproj_in%read_segment(params%oritype, params%projfile)
                nmics_tot = spproj_in%os_mic%get_noris()
                if( spproj_in%get_nintgs() == 0 ) THROW_HARD('No integrated micrograph to process!')
                ! init output project
                call spproj%read_non_data_segments(params%projfile)
                call spproj%projinfo%set(1,'projname', get_fbody(params%outfile,METADATA_EXT,separator=.false.))
                call spproj%projinfo%set(1,'projfile', params%outfile)
                params%projfile = trim(params%outfile) ! for builder later
                call spproj%os_mic%new(nmics_here, is_ptcl=.false.)
                cnt = 0
                do imic = fromto(1),fromto(2)
                    cnt = cnt + 1
                    call spproj_in%os_mic%get_ori(imic, o_tmp)
                    call spproj%os_mic%set_ori(cnt, o_tmp)
                enddo
                prog_write = .true.
                if( cline%defined('part') ) then 
                    prog_part = .true.
                    call progressfile_init_part(int(cline%get_rarg('part')))
                else
                    call progressfile_init()
                endif
                call spproj_in%kill
            endif
            ! input boxes
            if( cline%defined('dir_box') )then
                if( .not.file_exists(params%dir_box) )then
                    write(logfhandle,*)'Directory does not exist: ', trim(params%dir_box), 'simple_commander_preprocess::exec_extract'
                    THROW_HARD('box directory does not exist; exec_extract')
                endif
            endif
            ! sanity checks
            allocate(mics_mask(1:nmics_here), source=.false.)
            nmics  = 0
            nptcls = 0
            do imic = 1,nmics_here
                call spproj%os_mic%get_ori(imic, o_mic)
                state = 1
                if( o_mic%isthere('state') ) state = nint(o_mic%get('state'))
                if( state == 0 ) cycle
                if( .not. o_mic%isthere('imgkind') )cycle
                if( .not. o_mic%isthere('intg')    )cycle
                call o_mic%getter('imgkind', imgkind)
                if( trim(imgkind).ne.'mic') cycle
                call o_mic%getter('intg', mic_name)
                if( .not.file_exists(mic_name) )cycle
                ! box input
                if( cline%defined('dir_box') )then
                    box_fname = trim(params%dir_box)//'/'//fname_new_ext(basename(mic_name),'box')
                    if( .not.file_exists(box_fname) )cycle
                    call make_relativepath(CWD_GLOB,trim(box_fname),boxfile_name)
                    call spproj%os_mic%set_boxfile(imic, boxfile_name)
                else
                    boxfile_name = trim(o_mic%get_static('boxfile'))
                    if( .not.file_exists(boxfile_name) )cycle
                endif
                ! get number of frames from stack
                call find_ldim_nptcls(mic_name, lfoo, nframes )
                if( nframes > 1 ) THROW_HARD('multi-frame extraction not supported; exec_extract')
                ! update mask
                mics_mask(imic) = .true.
                nmics = nmics + 1
                ! image & box dimensions
                if( nmics == 1 )call find_ldim_nptcls(mic_name, ldim, ifoo)
                if( nptcls == 0 .and. .not.cline%defined('box') )then
                    if( nlines(boxfile_name) > 0 )then
                        call boxfile%new(boxfile_name, 1)
                        nptcls = boxfile%get_ndatalines()
                    endif
                    if( nptcls == 0 )then
                        call spproj%os_mic%set(imic, 'nptcls', 0.)
                        cycle
                    endif
                    allocate( boxdata(boxfile%get_nrecs_per_line(),nptcls) )
                    call boxfile%readNextDataLine(boxdata(:,1))
                    call boxfile%kill
                    params%box = nint(boxdata(3,1))
                endif
            enddo
            call spproj%write
            call spproj%kill
            params_glob%box = params%box ! for prepimgbatch
            ! actual extraction
            if( nmics == 0 )then
                ! done
            else
                if( params%box == 0 )THROW_HARD('box cannot be zero; exec_extract')
                ! init
                call build%build_spproj(params, cline)
                call build%build_general_tbox(params, cline, do3d=.false.)
                call micrograph%new([ldim(1),ldim(2),1], params%smpd)
                if( trim(params%extractfrommov).ne.'yes' ) call extractor%init_mic(params%box, (params%pcontrast .eq. 'black'))
                box_first = 0
                ! main loop
                iptcl_glob = 0 ! extracted particle index among ALL stacks
                prog = 0.0
                do imic = 1,nmics_here
                    if( .not.mics_mask(imic) )then
                        call build%spproj_field%set(imic, 'nptcls', 0.)
                        call build%spproj_field%set(imic, 'state', 0.)
                        cycle
                    endif
                    ! fetch micrograph
                    call build%spproj_field%get_ori(imic, o_mic)
                    call o_mic%getter('imgkind', imgkind)
                    boxfile_name = trim(o_mic%get_static('boxfile'))
                    ! box file
                    nptcls = 0
                    if( nlines(boxfile_name) > 0 )then
                        call boxfile%new(boxfile_name, 1)
                        nptcls = boxfile%get_ndatalines()
                    endif
                    if( nptcls == 0 ) cycle
                    call progress(imic,nmics_tot)
                    ! box checks
                    if(allocated(oris_mask))deallocate(oris_mask)
                    allocate(oris_mask(nptcls), source=.false.)
                    ! read box data & update mask
                    if(allocated(boxdata))deallocate(boxdata)
                    allocate( boxdata(boxfile%get_nrecs_per_line(),nptcls))
                    do iptcl=1,nptcls
                        call boxfile%readNextDataLine(boxdata(:,iptcl))
                        box = nint(boxdata(3,iptcl))
                        if( nint(boxdata(3,iptcl)) /= nint(boxdata(4,iptcl)) )then
                            THROW_HARD('only square windows allowed; exec_extract')
                        endif
                        ! modify coordinates if change in box (shift by half the difference)
                        if( box /= params%box ) boxdata(1:2,iptcl) = boxdata(1:2,iptcl) - real(params%box-box)/2.
                        if( .not.cline%defined('box') .and. nint(boxdata(3,iptcl)) /= params%box )then
                            write(logfhandle,*) 'box_current: ', nint(boxdata(3,iptcl)), 'box in params: ', params%box
                            THROW_HARD('inconsistent box sizes in box files; exec_extract')
                        endif
                        ! update particle mask & movie index
                        oris_mask(iptcl)  = (trim(params%outside).eq.'yes') .or. box_inside(ldim, nint(boxdata(1:2,iptcl)), params%box)
                    end do
                    ! update micrograph field
                    nptcls2extract = count(oris_mask)
                    call build%spproj_field%set(imic, 'nptcls', real(nptcls2extract))
                    if( nptcls2extract == 0 )then
                        ! no particles to extract
                        mics_mask(imic) = .false.
                        cycle
                    endif
                    if(allocated(ptcl_inds))deallocate(ptcl_inds)
                    allocate(ptcl_inds(nptcls2extract), source=0)
                    cnt = 0
                    do iptcl=1,nptcls
                        if( oris_mask(iptcl) )then
                            cnt = cnt + 1
                            ptcl_inds(cnt) = iptcl
                        endif
                    enddo
                    ! fetch ctf info
                    ctfparms      = o_mic%get_ctfvars()
                    ctfparms%smpd = params%smpd
                    if( o_mic%isthere('dfx') )then
                        if( .not.o_mic%isthere('cs') .or. .not.o_mic%isthere('kv') .or. .not.o_mic%isthere('fraca') )then
                            THROW_HARD('input lacks at least cs, kv or fraca; exec_extract')
                        endif
                    endif
                    ! output stack
                    call o_mic%getter('intg', mic_name)
                    ext   = fname2ext(trim(basename(mic_name)))
                    stack = trim(output_dir)//trim(EXTRACT_STK_FBODY)//trim(get_fbody(trim(basename(mic_name)), trim(ext)))//trim(STK_EXT)
                    ! init extraction
                    call prepimgbatch(nptcls2extract)
                    if( trim(params%extractfrommov).eq.'yes' )then
                        ! extraction from movie
                        if( trim(params%ctf).eq.'flip' .and. o_mic%isthere('dfx') )then
                            THROW_HARD('extractfrommov=yes does not support ctf=flip yet')
                        endif
                        call extractor%init_mov(o_mic, params%box, (params%pcontrast .eq. 'black'))
                        call extractor%extract_particles(ptcl_inds, nint(boxdata), build%imgbatch, stk_min,stk_max,stk_mean,stk_sdev)
                    else
                        ! extraction from micrograph
                        call micrograph%read(mic_name, 1)
                        ! phase-flip micrograph
                        if( cline%defined('ctf') )then
                            if( trim(params%ctf).eq.'flip' .and. o_mic%isthere('dfx') )then
                                tfun = ctf(ctfparms%smpd, ctfparms%kv, ctfparms%cs, ctfparms%fraca)
                                call micrograph%zero_edgeavg
                                call micrograph%fft
                                call tfun%apply_serial(micrograph, 'flip', ctfparms)
                                call micrograph%ifft
                                ! update stack ctf flag, mic flag unchanged
                                ctfparms%ctfflag = CTFFLAG_FLIP
                            endif
                        endif
                        ! extraction
                        call extractor%extract_particles_from_mic(micrograph, ptcl_inds, nint(boxdata), build%imgbatch,&
                            &stk_min,stk_max,stk_mean,stk_sdev)
                    endif
                    ! write stack
                    call stkio_w%open(trim(adjustl(stack)), params%smpd, 'write', box=params%box)
                    do i = 1,nptcls2extract
                        call stkio_w%write(i, build%imgbatch(i))
                    enddo
                    call stkio_w%close
                    ! update stack stats
                    call build%img%update_header_stats(trim(adjustl(stack)), [stk_min, stk_max, stk_mean, stk_sdev])
                    ! IMPORT INTO PROJECT
                    call build%spproj%add_stk(trim(adjustl(stack)), ctfparms)
                    ! add box coordinates to ptcl2D field only & updates patch-based defocus
                    l_ctfpatch = .false.
                    if( o_mic%isthere('ctfdoc') )then
                        ctfdoc = o_mic%get_static('ctfdoc')
                        if( file_exists(ctfdoc) )then
                            call ctffit%read_doc(ctfdoc)
                            l_ctfpatch = .true.
                        endif
                    endif
                    l_ogid_present = o_mic%isthere('ogid')
                    l_gid_present  = o_mic%isthere('gid')
                    !$omp parallel do schedule(static) default(shared) proc_bind(close)&
                    !$omp private(i,iptcl,iptcl_g,ptcl_pos,dfx,dfy)
                    do i = 1,nptcls2extract
                        iptcl    = ptcl_inds(i)
                        iptcl_g  = iptcl_glob + i
                        ptcl_pos = boxdata(1:2,iptcl)
                        ! updates particle position
                        call build%spproj%set_boxcoords(iptcl_g, nint(ptcl_pos))
                        ! updates particle defocus
                        if( l_ctfpatch )then
                            ptcl_pos = ptcl_pos+1.+real(params%box/2) !  center
                            call ctffit%pix2polyvals(ptcl_pos(1),ptcl_pos(2), dfx,dfy)
                            call build%spproj%os_ptcl2D%set_dfx(iptcl_g,dfx)
                            call build%spproj%os_ptcl2D%set_dfy(iptcl_g,dfy)
                            call build%spproj%os_ptcl3D%set_dfx(iptcl_g,dfx)
                            call build%spproj%os_ptcl3D%set_dfy(iptcl_g,dfy)
                        endif
                        ! update particle optics group id
                        if( l_ogid_present )then
                            call build%spproj%os_ptcl2D%set(iptcl_g,'ogid',o_mic%get('ogid'))
                            call build%spproj%os_ptcl3D%set(iptcl_g,'ogid',o_mic%get('ogid'))
                        endif
                        ! update particle group id
                        if( l_gid_present )then
                            call build%spproj%os_ptcl2D%set(iptcl_g,'gid',o_mic%get('gid'))
                            call build%spproj%os_ptcl3D%set(iptcl_g,'gid',o_mic%get('gid'))
                        endif
                    end do
                    !$omp end parallel do
                    ! global particle count
                    iptcl_glob = iptcl_glob + nptcls2extract
                    ! clean
                    call boxfile%kill
                    call ctffit%kill
                    ! progress
                    if(prog_write) then
                        if( (real(imic) / real(nmics_here)) > prog + 0.05 ) then
                            prog = real(imic) / real(nmics_here)
                            if(prog_part) then 
                                call progressfile_update_part(int(cline%get_rarg('part')), prog)
                            else
                                call progressfile_update(prog)
                            endif
                        endif
                    endif
                enddo
                call killimgbatch
                ! write
                call build%spproj%write
            endif
            ! end gracefully
            call extractor%kill
            call micrograph%kill
            call o_mic%kill
            call o_tmp%kill
            call progressfile_update(1.0)
            call qsys_job_finished('simple_commander_preprocess :: exec_extract')
            call simple_end('**** SIMPLE_EXTRACT NORMAL STOP ****')
        end subroutine exec_extract
    
        subroutine exec_reextract_distr( self, cline )
            class(reextract_commander_distr), intent(inout) :: self
            class(cmdline),           intent(inout) :: cline !< command line input
            type(parameters)                        :: params
            type(sp_project)                        :: spproj
            type(sp_project),           allocatable :: spproj_parts(:)
            type(qsys_env)                          :: qenv
            type(chash)                             :: job_descr
            type(ori)                               :: o_mic, o
            type(oris)                              :: os_stk
            type(chash),                allocatable :: part_params(:)
            character(len=LONGSTRLEN),  allocatable :: boxfiles(:), stktab(:), parts_fname(:)
            character(len=:),           allocatable :: mic_name, imgkind
            integer,                    allocatable :: parts(:,:)
            integer :: imic,i,nmics_tot,numlen,nmics,cnt,state,istk,nstks,ipart,stkind,nptcls
            if( cline%defined('ctf') )then
                if( cline%get_carg('ctf').ne.'flip' .and. cline%get_carg('ctf').ne.'no' )then
                    THROW_HARD('Only CTF=NO/FLIP are allowed')
                endif
            endif
            if( .not. cline%defined('mkdir')     )     call cline%set('mkdir',          'yes')
            if( .not. cline%defined('pcontrast') )     call cline%set('pcontrast',    'black')
            if( .not. cline%defined('oritype')   )     call cline%set('oritype',     'ptcl3D')
            if( .not. cline%defined('extractfrommov')) call cline%set('extractfrommov',  'no')
            call params%new(cline)
            call cline%set('mkdir', 'no')
            ! read in integrated movies
            call spproj%read( params%projfile )
            call spproj%update_projinfo( cline )
            if( spproj%get_nintgs() == 0 ) THROW_HARD('No integrated micrograph to process!')
            if( spproj%get_nstks() == 0 ) THROW_HARD('This project file does not contain stacks!')
            nmics_tot = spproj%os_mic%get_noris()
            if( nmics_tot < params%nparts )then
                params%nparts = nmics_tot
            endif
            ! sanity checks
            nmics  = 0
            do imic = 1, nmics_tot
                call spproj%os_mic%get_ori(imic, o_mic)
                state = 1
                if( o_mic%isthere('state') ) state = nint(o_mic%get('state'))
                if( state == 0 ) cycle
                if( .not. o_mic%isthere('imgkind') )cycle
                if( .not. o_mic%isthere('intg')    )cycle
                call o_mic%getter('imgkind', imgkind)
                if( trim(imgkind).ne.'mic') cycle
                call o_mic%getter('intg', mic_name)
                if( .not.file_exists(mic_name) )cycle
                ! update counter
                nmics = nmics + 1
                ! removes boxfile from micrographs
                call spproj%os_mic%delete_entry(imic,'boxfile')
            enddo
            if( nmics == 0 )then
                THROW_WARN('No particles to re-extract! exec_reextract')
                return
            endif
            call spproj%os_mic%kill
            call spproj%os_stk%kill
            call spproj%os_ptcl2D%kill
            call spproj%os_ptcl3D%kill
            ! DISTRIBUTED EXTRACTION
            ! setup the environment for distributed execution
            parts = split_nobjs_even(nmics_tot, params%nparts)
            allocate(part_params(params%nparts))
            do ipart=1,params%nparts
                call part_params(ipart)%new(2)
                call part_params(ipart)%set('fromp',int2str(parts(ipart,1)))
                call part_params(ipart)%set('top',  int2str(parts(ipart,2)))
            end do
            call qenv%new(params%nparts)
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule & clean
            call qenv%gen_scripts_and_schedule_jobs( job_descr, algnfbody=trim(ALGN_FBODY), part_params=part_params, array=L_USE_SLURM_ARR)
            ! ASSEMBLY
            allocate(spproj_parts(params%nparts),parts_fname(params%nparts))
            numlen = len(int2str(params%nparts))
            do ipart = 1,params%nparts
                parts_fname(ipart) = trim(ALGN_FBODY)//int2str_pad(ipart,numlen)//trim(METADATA_EXT)
            enddo
            ! copy updated micrographs
            cnt   = 0
            nmics = 0
            do ipart = 1,params%nparts
                call spproj_parts(ipart)%read_segment('mic',parts_fname(ipart))
                nmics = nmics + spproj_parts(ipart)%os_mic%get_noris()
            enddo
            if( nmics > 0 )then
                call spproj%os_mic%new(nmics, is_ptcl=.false.)
                ! transfer stacks
                cnt   = 0
                nstks = 0
                do ipart = 1,params%nparts
                    do imic = 1,spproj_parts(ipart)%os_mic%get_noris()
                        cnt = cnt + 1
                        call spproj%os_mic%transfer_ori(cnt, spproj_parts(ipart)%os_mic, imic)
                    enddo
                    call spproj_parts(ipart)%kill
                    call spproj_parts(ipart)%read_segment('stk',parts_fname(ipart))
                    nstks = nstks + spproj_parts(ipart)%os_stk%get_noris()
                enddo
                if( nstks /= nmics ) THROW_HARD('Inconstistent number of stacks in individual projects')
                ! generates stacks table
                call os_stk%new(nstks, is_ptcl=.false.)
                allocate(stktab(nstks))
                cnt = 0
                do ipart = 1,params%nparts
                    do istk = 1,spproj_parts(ipart)%os_stk%get_noris()
                        cnt = cnt + 1
                        call os_stk%transfer_ori(cnt, spproj_parts(ipart)%os_stk, istk)
                        stktab(cnt) = os_stk%get_static(cnt,'stk')
                    enddo
                    call spproj_parts(ipart)%kill
                enddo
                ! import stacks into project
                call spproj%add_stktab(stktab,os_stk)
                call os_stk%kill
                ! 2D/3D parameters, transfer everything but stack index
                cnt = 0
                do ipart = 1,params%nparts
                    call spproj_parts(ipart)%read_segment('ptcl2D',parts_fname(ipart))
                    call spproj_parts(ipart)%read_segment('ptcl3D',parts_fname(ipart))
                    nptcls = spproj_parts(ipart)%os_ptcl2D%get_noris()
                    if( nptcls /= spproj_parts(ipart)%os_ptcl3D%get_noris())then
                        THROW_HARD('Inconsistent number of particles')
                    endif
                    do i = 1,nptcls
                        cnt    = cnt + 1
                        stkind = nint(spproj%os_ptcl2D%get(cnt,'stkind'))
                        call spproj%os_ptcl2D%transfer_ori(cnt, spproj_parts(ipart)%os_ptcl2D, i)
                        call spproj%os_ptcl3D%transfer_ori(cnt, spproj_parts(ipart)%os_ptcl3D, i)
                        call spproj%os_ptcl2D%set(cnt,'stkind',real(stkind))
                        call spproj%os_ptcl3D%set(cnt,'stkind',real(stkind))
                    enddo
                    call spproj_parts(ipart)%kill
                enddo
            endif
            ! final write
            call spproj%write( params%projfile )
            ! clean-up
            call qsys_cleanup
            call spproj%kill
            deallocate(spproj_parts,part_params)
            call o_mic%kill
            call o%kill
            ! end gracefully
            call simple_end('**** SIMPLE_REEXTRACT_DISTR NORMAL STOP ****')
            contains
    
                character(len=LONGSTRLEN) function boxfile_from_mic(mic)
                    character(len=*), intent(in) :: mic
                    character(len=LONGSTRLEN)    :: box_from_mic
                    integer :: ibox
                    box_from_mic     = fname_new_ext(basename(mic),'box')
                    boxfile_from_mic = NIL
                    do ibox=1,size(boxfiles)
                        if(trim(basename(boxfiles(ibox))).eq.trim(box_from_mic))then
                            boxfile_from_mic = trim(boxfiles(ibox))
                            return
                        endif
                    enddo
                end function boxfile_from_mic
    
        end subroutine exec_reextract_distr
    
        subroutine exec_reextract( self, cline )
            use simple_ctf,                 only: ctf
            use simple_strategy2D3D_common, only: prepimgbatch, killimgbatch
            use simple_particle_extractor,  only: ptcl_extractor
            class(reextract_commander), intent(inout) :: self
            class(cmdline),             intent(inout) :: cline !< command line input
            type(parameters)              :: params
            type(sp_project)              :: spproj, spproj_in
            type(builder)                 :: build
            type(image)                   :: micrograph
            type(ori)                     :: o_mic, o_stk
            type(ctf)                     :: tfun
            type(ctfparams)               :: ctfparms
            type(stack_io)                :: stkio_w
            type(ptcl_extractor)          :: extractor
            character(len=:), allocatable :: mic_name, imgkind, ext
            logical,          allocatable :: mic_mask(:), ptcl_mask(:)
            integer,          allocatable :: mic2stk_inds(:), boxcoords(:,:), ptcl_inds(:)
            character(len=LONGSTRLEN)     :: stack, rel_stack
            real    :: prev_shift(2), shift2d(2), shift3d(2), stk_min,stk_max,stk_mean,stk_sdev
            integer :: i,nframes,imic,iptcl,nmics,prev_box,box_foo,cnt,nmics_tot,nptcls,stk_ind
            integer :: prev_pos(2),new_pos(2),ishift(2),ldim(3),ldim_foo(3),fromp,top,istk,nptcls2extract
            logical :: l_3d
            call cline%set('mkdir','no')
            call params%new(cline)
            ! set normalization radius
            params%msk = RADFRAC_NORM_EXTRACT * real(params%box/2)
            ! whether to use shifts from 2D or 3D
            l_3d = .true.
            if(cline%defined('oritype')) l_3d = trim(params%oritype)=='ptcl3D'
            ! read in integrated movies
            call spproj_in%read_segment('mic', params%projfile)
            nmics_tot = spproj_in%os_mic%get_noris()
            if( spproj_in%get_nintgs() == 0 ) THROW_HARD('No integrated micrograph to process!')
            call spproj_in%read_segment('stk', params%projfile)
            ! sanity checks, dimensions & indexing
            box_foo  = 0
            prev_box = 0
            ldim_foo = 0
            ldim     = 0
            allocate(mic2stk_inds(nmics_tot), source=0)
            allocate(mic_mask(nmics_tot),     source=.false.)
            stk_ind = 0
            do imic = 1,nmics_tot
                if( imic > params%top ) exit
                call spproj_in%os_mic%get_ori(imic, o_mic)
                if( o_mic%isthere('state') )then
                    if( o_mic%get_state() == 0 )cycle
                endif
                if( .not. o_mic%isthere('imgkind') )cycle
                if( .not. o_mic%isthere('intg')    )cycle
                call o_mic%getter('imgkind', imgkind)
                if( trim(imgkind).ne.'mic') cycle
                ! find next selected stack
                do istk=stk_ind,spproj_in%os_stk%get_noris()
                    stk_ind = stk_ind+1
                    if( spproj_in%os_stk%isthere(stk_ind,'state') )then
                        if( spproj_in%os_stk%get_state(stk_ind) == 1 ) exit
                    else
                        exit
                    endif
                enddo
                ! update index & mask
                if( imic>=params%fromp .and. imic<=params%top )then
                    mic_mask(imic) = .true.
                    mic2stk_inds(imic) = stk_ind ! index to os_stk
                endif
            enddo
            nmics = count(mic_mask)
            if( nmics > 0 )then
                call build%build_general_tbox(params, cline, do3d=.false.)
                call spproj_in%read_segment('ptcl2D', params%projfile)
                ! sanity checks
                do imic = 1,nmics_tot
                    if( .not.mic_mask(imic) )cycle
                    ! sanity checks
                    call spproj_in%os_mic%get_ori(imic, o_mic)
                    call o_mic%getter('intg', mic_name)
                    if( .not.file_exists(mic_name) )cycle
                    call find_ldim_nptcls(mic_name, ldim_foo, nframes )
                    if( nframes > 1 ) THROW_HARD('multi-frame extraction not supported; exec_reextract')
                    if( any(ldim == 0) ) ldim = ldim_foo
                    stk_ind = mic2stk_inds(imic)
                    call spproj_in%os_stk%get_ori(stk_ind, o_stk)
                    fromp   = nint(o_stk%get('fromp'))
                    top     = nint(o_stk%get('top'))
                    box_foo = nint(o_stk%get('box'))
                    if( prev_box == 0 ) prev_box = box_foo
                    if( prev_box /= box_foo ) THROW_HARD('Inconsistent box size; exec_reextract')
                enddo
                if( .not.cline%defined('box') ) params%box = prev_box
                if( is_odd(params%box) ) THROW_HARD('Box size must be of even dimension! exec_extract')
                ! extraction
                write(logfhandle,'(A)')'>>> EXTRACTING... '
                call spproj_in%read_segment('ptcl3D', params%projfile)
                allocate(ptcl_mask(spproj_in%os_ptcl2D%get_noris()),source=.false.)
                call micrograph%new([ldim(1),ldim(2),1], params%smpd)
                if( trim(params%extractfrommov).ne.'yes' ) call extractor%init_mic(params%box, (params%pcontrast .eq. 'black'))
                do imic = params%fromp,params%top
                    if( .not.mic_mask(imic) ) cycle
                    stk_ind = mic2stk_inds(imic)
                    call spproj_in%os_mic%get_ori(imic, o_mic)
                    call spproj_in%os_stk%get_ori(stk_ind, o_stk)
                    call o_mic%getter('intg', mic_name)
                    ctfparms = o_mic%get_ctfvars()
                    fromp    = nint(o_stk%get('fromp'))
                    top      = nint(o_stk%get('top'))
                    ext      = fname2ext(trim(basename(mic_name)))
                    stack    = trim(EXTRACT_STK_FBODY)//trim(get_fbody(trim(basename(mic_name)), trim(ext)))//trim(STK_EXT)
                    ! updating shifts, positions, states and doc
                    if( allocated(boxcoords) ) deallocate(boxcoords)
                    allocate(boxcoords(2,fromp:top),source=0)
                    do iptcl=fromp,top
                        if( spproj_in%os_ptcl2D%get_state(iptcl) == 0 ) cycle
                        if( spproj_in%os_ptcl3D%get_state(iptcl) == 0 ) cycle
                        ! previous position & shift
                        call spproj_in%get_boxcoords(iptcl, prev_pos)
                        if( l_3d )then
                            prev_shift = spproj_in%os_ptcl3D%get_2Dshift(iptcl)
                        else
                            prev_shift = spproj_in%os_ptcl2D%get_2Dshift(iptcl)
                        endif
                        ! calc new position & shift
                        ishift  = nint(prev_shift)
                        new_pos = prev_pos - ishift
                        if( prev_box /= params%box ) new_pos = new_pos + (prev_box-params%box)/2
                        boxcoords(:,iptcl) = new_pos
                        if( box_inside(ldim, new_pos, params%box) )then
                            ptcl_mask(iptcl) = .true.
                            ! updates picking position
                            call spproj_in%set_boxcoords(iptcl, new_pos)
                            ! updates shifts
                            if( l_3d )then
                                shift2d = spproj_in%os_ptcl2D%get_2Dshift(iptcl) - real(ishift)
                                shift3d = prev_shift - real(ishift)
                            else
                                shift2d = prev_shift - real(ishift)
                                shift3d = spproj_in%os_ptcl3D%get_2Dshift(iptcl) - real(ishift)
                            endif
                            call spproj_in%os_ptcl2D%set_shift(iptcl, shift2d)
                            call spproj_in%os_ptcl3D%set_shift(iptcl, shift3d)
                        else
                            ! excluded
                            call spproj_in%os_ptcl2D%set_state(iptcl, 0)
                            call spproj_in%os_ptcl3D%set_state(iptcl, 0)
                        endif
                    enddo
                    nptcls2extract = count(ptcl_mask(fromp:top))
                    if( nptcls2extract > 0 )then
                        if( allocated(ptcl_inds) ) deallocate(ptcl_inds)
                        allocate(ptcl_inds(nptcls2extract),source=0)
                        cnt = 0
                        do iptcl = fromp,top
                            if( .not.ptcl_mask(iptcl) ) cycle
                            cnt = cnt + 1
                            ptcl_inds(cnt) = iptcl
                            ! updating index of particle in stack
                            call spproj_in%os_ptcl2D%set(iptcl, 'indstk', real(cnt))
                            call spproj_in%os_ptcl3D%set(iptcl, 'indstk', real(cnt))
                        enddo
                        ptcl_inds = ptcl_inds -fromp+1 ! because indexing range lost when passed to extractor
                        call prepimgbatch(nptcls2extract)
                        if( trim(params%extractfrommov).eq.'yes' )then
                            ! extraction from movie
                            if( trim(params%ctf).eq.'flip' .and. o_mic%isthere('dfx') )then
                                THROW_HARD('extractfrommov=yes does not support ctf=flip yet')
                            endif
                            call extractor%init_mov(o_mic, params%box, (params%pcontrast .eq. 'black'))
                            call extractor%extract_particles(ptcl_inds, boxcoords, build%imgbatch, stk_min,stk_max,stk_mean,stk_sdev)
                        else
                            ! preprocess micrograph
                            call micrograph%read(mic_name)
                            if( ctfparms%ctfflag == CTFFLAG_FLIP )then
                                if( o_mic%isthere('dfx') )then
                                    ! phase flip micrograph
                                    tfun = ctf(ctfparms%smpd, ctfparms%kv, ctfparms%cs, ctfparms%fraca)
                                    call micrograph%zero_edgeavg
                                    call micrograph%fft
                                    call tfun%apply_serial(micrograph, 'flip', ctfparms)
                                    call micrograph%ifft
                                endif
                            endif
                            ! extraction
                            call extractor%extract_particles_from_mic(micrograph, ptcl_inds, boxcoords, build%imgbatch,&
                                &stk_min,stk_max,stk_mean,stk_sdev)
                        endif
                        ! write stack
                        call stkio_w%open(trim(adjustl(stack)), params%smpd, 'write', box=params%box)
                        do i = 1,nptcls2extract
                            call stkio_w%write(i, build%imgbatch(i))
                        enddo
                        call stkio_w%close
                        call micrograph%update_header_stats(trim(adjustl(stack)), [stk_min, stk_max, stk_mean, stk_sdev])
                        call make_relativepath(CWD_GLOB, stack, rel_stack)
                        call spproj_in%os_stk%set(stk_ind,'stk',   rel_stack)
                        call spproj_in%os_stk%set(stk_ind,'box',   real(params%box))
                        call spproj_in%os_stk%set(stk_ind,'nptcls',real(nptcls2extract))
                        call spproj_in%os_mic%set(imic,   'nptcls',real(nptcls2extract))
                        call spproj_in%os_mic%delete_entry(imic,'boxfile')
                    else
                        ! all particles in this micrograph excluded
                        call spproj_in%os_stk%set(stk_ind,'state',0.)
                        call spproj_in%os_mic%set(imic,'state',0.)
                        mic_mask(imic) = .false.
                        mic2stk_inds(imic) = 0
                    endif
                enddo
            endif
            call extractor%kill
            call killimgbatch
            ! OUTPUT
            call spproj%read_non_data_segments(params%projfile)
            call spproj%projinfo%set(1,'projname', get_fbody(params%outfile,METADATA_EXT,separator=.false.))
            call spproj%projinfo%set(1,'projfile', params%outfile)
            nmics = count(mic_mask)
            ! transfer mics & stk
            call spproj%os_mic%new(nmics, is_ptcl=.false.)
            call spproj%os_stk%new(nmics, is_ptcl=.false.)
            nptcls = count(ptcl_mask)
            cnt = 0
            do imic = params%fromp,params%top
                if( .not.mic_mask(imic) )cycle
                cnt = cnt+1
                call spproj%os_mic%transfer_ori(cnt, spproj_in%os_mic, imic)
                stk_ind = mic2stk_inds(imic)
                call spproj%os_stk%transfer_ori(cnt, spproj_in%os_stk, stk_ind)
            enddo
            ! transfer particles
            nptcls = count(ptcl_mask)
            call spproj%os_ptcl2D%new(nptcls, is_ptcl=.true.)
            call spproj%os_ptcl3D%new(nptcls, is_ptcl=.true.)
            cnt = 0
            do iptcl = 1,size(ptcl_mask)
                if( .not.ptcl_mask(iptcl) )cycle
                cnt = cnt+1
                call spproj%os_ptcl2D%transfer_ori(cnt, spproj_in%os_ptcl2D, iptcl)
                call spproj%os_ptcl3D%transfer_ori(cnt, spproj_in%os_ptcl3D, iptcl)
            enddo
            call spproj_in%kill
            ! final write
            call spproj%write(params%outfile)
            write(logfhandle,'(A,I8)')'>>> RE-EXTRACTED  PARTICLES: ', nptcls
            ! end gracefully
            call qsys_job_finished('simple_commander_preprocess :: exec_reextract')
            call build%kill_general_tbox
            call o_mic%kill
            call o_stk%kill
            call simple_end('**** SIMPLE_REEXTRACT NORMAL STOP ****')
        end subroutine exec_reextract
    
        subroutine exec_pick_extract( self, cline )
            use simple_sp_project,  only: sp_project
            use simple_picker_iter, only: picker_iter
            class(pick_extract_commander), intent(inout) :: self
            class(cmdline),                intent(inout) :: cline
            type(parameters)              :: params
            type(ori)                     :: o_mic
            type(picker_iter)             :: piter
            type(extract_commander)       :: xextract
            type(cmdline)                 :: cline_extract
            type(sp_project)              :: spproj
            character(len=:), allocatable :: micname, output_dir_picker, fbody, output_dir_extract
            character(len=LONGSTRLEN)     :: boxfile
            integer :: fromto(2), imic, ntot, nptcls_out, state
            ! set oritype
            call cline%set('oritype', 'mic')
            ! parse parameters
            call params%new(cline)
            if( params%stream.ne.'yes' ) THROW_HARD('streaming only application')
            ! read in movies
            call spproj%read( params%projfile )
            if( spproj%get_nintgs() == 0 ) THROW_HARD('no micrograph to process!')
            ! output directories
            if( params%stream.eq.'yes' )then
                output_dir_picker  = trim(DIR_PICKER)
                output_dir_extract = trim(DIR_EXTRACT)
                call simple_mkdir(output_dir_picker, errmsg="commander_preprocess :: preprocess; ")
                call simple_mkdir(output_dir_extract,errmsg="commander_preprocess :: preprocess; ")
            else
                output_dir_picker  = PATH_HERE
                output_dir_extract = PATH_HERE
            endif
            ! command lines
            cline_extract = cline
            call cline_extract%set('dir', trim(output_dir_extract))
            call cline_extract%set('pcontrast', params%pcontrast)
            if( cline%defined('box_extract') )call cline_extract%set('box', real(params%box_extract))
            call cline%delete('box')
            call cline_extract%delete('box_extract')
            ! file name
            if( cline%defined('fbody') )then
                fbody = trim(params%fbody)
            else
                fbody = ''
            endif
            ! range
            if( params%stream.eq.'yes' )then
                fromto(:) = 1
            else
                fromto(:) = [params%fromp, params%top]
            endif
            ntot = fromto(2) - fromto(1) + 1
            ! loop over exposures (movies)
            do imic = fromto(1),fromto(2)
                ! fetch movie orientation
                call spproj%os_mic%get_ori(imic, o_mic)
                ! sanity check
                state = 1
                if( o_mic%isthere('state') ) state = nint(o_mic%get('state'))
                if( state == 0 ) cycle
                if( .not.o_mic%isthere('intg')   )cycle
                call o_mic%getter('intg', micname)
                if( .not.file_exists(micname)) cycle
                ! picker
                params_glob%lp = max(params%fny, params%lp_pick)
                call piter%iterate(cline, params_glob%smpd, micname, boxfile, nptcls_out, output_dir_picker)
                call o_mic%set_boxfile(boxfile, nptcls=nptcls_out)
                ! update project
                call spproj%os_mic%set_ori(imic, o_mic)
                call spproj%write_segment_inside(params%oritype)
                ! extract particles
                call xextract%execute(cline_extract)
                call spproj%kill
            end do
            if( params%stream .eq. 'yes' )then
                ! nothing to do, extract did it
            else
                call binwrite_oritab(params%outfile, spproj, spproj%os_mic, fromto, isegment=MIC_SEG)
            endif
            ! end gracefully
            call qsys_job_finished(  'simple_commander_preprocess :: exec_pick_extract' )
            call o_mic%kill
            call piter%kill
            call simple_end('**** SIMPLE_PICK_EXTRACT NORMAL STOP ****')
        end subroutine exec_pick_extract
    
        subroutine exec_make_pickrefs( self, cline )
            use simple_projector_hlev, only: reproject
            class(make_pickrefs_commander), intent(inout) :: self
            class(cmdline),                 intent(inout) :: cline
            type(parameters)              :: params
            type(stack_io)                :: stkio_r
            type(sym)                     :: pgrpsyms
            type(image)                   :: ref2D
            type(image),      allocatable :: projs(:)
            integer, parameter :: NREFS=100, NPROJS=20
            real    :: ang, rot, smpd_here
            integer :: nrots, iref, irot, ldim(3), ldim_here(3), ncavgs, icavg
            integer :: cnt, norefs
            ! error check
            if( cline%defined('vol1') ) THROW_HARD('vol1 input no longer supported, use prg=reproject to generate 20 2D references')
            if( .not.cline%defined('pickrefs') ) THROW_HARD('PICKREFS must be informed!')
            ! set defaults
            call cline%set('oritype', 'mic')
            if( .not. cline%defined('pcontrast') ) call cline%set('pcontrast','black')
            ! parse parameters
            call params%new(cline)
            if( params%stream.eq.'yes' ) THROW_HARD('not a streaming application')
            if( .not. cline%defined('pgrp') ) params%pgrp = 'd1' ! only northern hemisphere
            ! point-group object
            call pgrpsyms%new(trim(params%pgrp))
            ! read selected cavgs
            call find_ldim_nptcls(params%pickrefs, ldim_here, ncavgs, smpd=smpd_here)
            if( smpd_here < 0.01 ) THROW_HARD('Invalid sampling distance for the cavgs (should be in MRC format)')
            ldim_here(3) = 1
            allocate( projs(ncavgs) )
            call stkio_r%open(params%pickrefs, params%smpd, 'read', bufsz=ncavgs)
            do icavg=1,ncavgs
                call projs(icavg)%new(ldim_here, smpd_here)
                call stkio_r%read(icavg, projs(icavg))
                call scale_ref(projs(icavg), params%smpd)
            end do
            call stkio_r%close
            nrots  = nint( real(NREFS)/real(ncavgs) )
            norefs = ncavgs
            ! expand in in-plane rotation and write to file
            if( nrots > 1 )then
                call ref2D%new([ldim(1),ldim(2),1], params%smpd)
                ang = 360./real(nrots)
                rot = 0.
                cnt = 0
                do iref=1,norefs
                    do irot=1,nrots
                        cnt = cnt + 1
                        call projs(iref)%rtsq(rot, 0., 0., ref2D)
                        if(params%pcontrast .eq. 'black') call ref2D%neg
                        call ref2D%write(trim(PICKREFS)//params%ext, cnt)
                        rot = rot + ang
                    end do
                end do
            else
                ! should never happen
                do iref=1,norefs
                    if(params%pcontrast .eq. 'black') call projs(iref)%neg
                    call projs(iref)%write(trim(PICKREFS)//params%ext, iref)
                end do
            endif
            ! end gracefully
            call simple_touch('MAKE_PICKREFS_FINISHED', errmsg='In: commander_preprocess::exec_make_pickrefs')
            call simple_end('**** SIMPLE_MAKE_PICKREFS NORMAL STOP ****')
    
            contains
    
                subroutine scale_ref(refimg, smpd_target)
                    class(image), intent(inout) :: refimg
                    real,         intent(in)    :: smpd_target
                    type(image) :: targetimg
                    integer     :: ldim_ref(3), ldim_target(3)
                    real        :: smpd_ref, scale
                    smpd_ref = refimg%get_smpd()
                    scale    = smpd_target / smpd_ref / params%scale
                    if( is_equal(scale,1.) )then
                        ldim = ldim_here
                        return
                    endif
                    ldim_ref       = refimg%get_ldim()
                    ldim_target(1) = round2even(real(ldim_ref(1))/scale)
                    ldim_target(2) = ldim_target(1)
                    ldim_target(3) = 1
                    if( refimg%is_3d() )ldim_target(3) = ldim_target(1)
                    call refimg%norm
                    if( scale > 1. )then
                        ! downscaling
                        call refimg%fft
                        call refimg%clip_inplace(ldim_target)
                        call refimg%ifft
                    else
                        call targetimg%new(ldim_target, smpd_target)
                        call refimg%fft
                        call refimg%pad(targetimg, backgr=0.)
                        call targetimg%ifft
                        refimg = targetimg
                        call targetimg%kill
                    endif
                    ! updates dimensions
                    ldim = ldim_target
                end subroutine
    
        end subroutine exec_make_pickrefs
    
        ! UTILITIES
    
        logical function box_inside( ildim, coord, box )
            integer, intent(in) :: ildim(3), coord(2), box
            integer             :: fromc(2), toc(2)
            fromc  = coord+1       ! compensate for the c-range that starts at 0
            toc    = fromc+(box-1) ! the lower left corner is 1,1
            box_inside = .true.    ! box is inside
            if( any(fromc < 1) .or. toc(1) > ildim(1) .or. toc(2) > ildim(2) ) box_inside = .false.
        end function box_inside
    
    end module simple_commander_preprocess
    