local function printtestdescription(s)
    print()
    print("======================================")
    print(s)
    print("======================================")
end

local std = {}
std.io = terralib.includec("stdio.h")
std.lib = terralib.includec("stdlib.h")

--implementation of a smart (shared) pointer type
struct A{
    data : &int     --underlying data ptr
}

A.methods.refcounter = terra(self : &A)
    if self.data ~= nil then
        return [&int8](self.data+1)
    end
    return nil
end

A.methods.increaserefcounter = terra(self : &A)
    var ptr = self:refcounter()
    if  ptr ~= nil then
        @ptr = @ptr+1
    end
end

A.methods.decreaserefcounter = terra(self : &A)
    var ptr = self:refcounter()
    if  ptr ~= nil then
        @ptr = @ptr-1
    end
end

--initialization of pointer variables
A.metamethods.__init = terra(self : &A)
    std.io.printf("__init: initializing object. start.\n")
    self.data = nil       -- initialize data pointer to nil
    std.io.printf("__init: initializing object. return.\n")
end

--move-assignment operation
A.metamethods.__move = terra(self : &A)
    std.io.printf("__move: moving object. start.\n")
    defer std.io.printf("__move: moving object. return.\n")
    var tmp : A
    tmp.data = self.data     --moving data to temporary variable
    self.data = nil          --setting data of self to nil, which makes it safe to delete
    return tmp
end

--destructor
A.metamethods.__dtor = terra(self : &A)
    std.io.printf("__dtor: calling destructor. start\n")
    defer std.io.printf("__dtor: calling destructor. return\n")
    --if uninitialized then do nothing
    if self.data == nil then
        return
    end
    --the reference counter is `nil`, `1` or `> 1`.
    --free memory if the last shared pointer obj runs out of life
    if @self:refcounter() == 1 then
        std.io.printf("__dtor: reference counter: %d -> %d.\n", @self:refcounter(), @self:refcounter()-1)
        std.io.printf("__dtor: free'ing memory.\n")
        std.lib.free(self.data)
        self.data = nil         --reinitialize data ptr
    --otherwise reduce reference counter
    else
        self:decreaserefcounter()             --decrease the reference counter
        std.io.printf("__dtor: reference counter: %d -> %d.\n", @self:refcounter()+1, @self:refcounter())
    end
end

--copy-assignment operation
--chosen to operate only on self, which is flexible enough to implement the behavior of
--a shared smart pointer type
A.metamethods.__copy = terra(self : &A)
    std.io.printf("__copy: calling copy-assignment operator. start\n")
    defer std.io.printf("__copy: calling copy-assignment operator. return\n")
    self:increaserefcounter()
    return self
end

local alloc = terra()
    std.io.printf("alloc: allocating memory. start\n")
    defer std.io.printf("alloc: allocating memory. return.\n")
    var x : A
    --heap allocation for `data` with the reference counter `refcount` stored in
    --its tail
    var head = sizeof(int)
    var tail = sizeof(int8)
    x.data = [&int](std.lib.malloc(head+tail))
    --initializing the reference counter to one
    @x.data = 10
    @x:refcounter() = 1
    return x
end

--testing vardef and copy assign
local terra test0()
    var a : A
    std.io.printf("main: a.refcount: %p\n", a:refcounter())
    a = alloc()
    std.io.printf("main: a.data: %d\n", @a.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    var b = a
    std.io.printf("main: b.data: %d\n", @b.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    std.io.printf("main: b.refcount: %d\n", @b:refcounter())
    std.io.printf("main: a.refcount: %p\n", a:refcounter())
    std.io.printf("main: b.refcount: %p\n", b:refcounter())
end

--testing var and copy assign
local terra test1()
    var a : A, b : A
    std.io.printf("main: a.refcount: %p\n", a:refcounter())
    a = alloc()
    std.io.printf("main: a.data: %d\n", @a.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    b = a
    std.io.printf("main: b.data: %d\n", @b.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    std.io.printf("main: b.refcount: %d\n", @b:refcounter())
    std.io.printf("main: a.refcount: %p\n", a:refcounter())
    std.io.printf("main: b.refcount: %p\n", b:refcounter())
end

printtestdescription("smartptr - vardef assignment.")
test0()

printtestdescription("smartptr - copy assignment.")
test1()