# pijpkijk: Node Graph Viewer MVP Plan

* Allow selecting bezier connections (should get a red border), and drawn in the priority.
* Rework pipewire stuff, its been vibed and its shite
* Use of one `io_uring` master loop.
    * Use `pw_loop` rather than `pw_thread_loop`, unwrapping the fd using `pw_loop_get_fd()`
    * Use `VK_KHR_external_fence_fd` extension to get an eventfd for the 
    * SDL3 
        -> could this also give me an fd for `io_uring`.
        -> It cant, so go for wayland + alsa instead of SDL3
    * Then: `io_uring` event loop
