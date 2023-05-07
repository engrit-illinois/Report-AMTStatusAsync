# Summary
This is a slightly modified version of [Report-AMTStatus]() which polls computers asynchronously instead of sequentially.  

It's mostly just a hack, which sacrifices properly ordered log output and progress percentage reporting for the sake of speed. It was _not_ designed from the ground up to be asynchronous.  

The entire readme of `Remote-AMTStatus` applies with the exception of a single new parameter, documented below.  

# Parameters

### -ThrottleLimit \<int\>
Optional integer.  
Specifies the maximum number of computers to asynchronously poll simultaneously.  
Default is `20`.

# Notes
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.
