# pijpkijk: Node Graph Viewer MVP Plan
Long term goal: feature parity with helvum

* I have some LLM generated sections I don't understand
    -> text rendering is the prime example, thats fully vibed because I couldnt be asked
* Have depth buffering now, but somehow the anti-aliasing has a cooked alpha channel. Can do some hacks, but its
    hacks... Must be a better way to do it.
* Make it so that we can delete nodes
* Make it so that we can connect nodes 
* Add feature where we can monitor nodes by creating rtp nodes ? figure out if it is possible
* Add a left and a right monitor feature for the left and right ear. If 1 specified its mono
    -> probably have loudness normalization
* Add RFFT of the channels as a background, either mono or dual channel
* Fix dependencies to be maximally static
* Consider if the app is mature if we wanna package it somehow? Can be a nice learning
