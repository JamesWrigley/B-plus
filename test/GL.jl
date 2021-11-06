# Check some basic facts.
@bp_check(GL.gl_type(GL.Ptr_Uniform) === GLint,
          "GL.Ptr_Uniform's original type is not GLint, but ",
             GL.gl_type(GL.Ptr_Uniform))
@bp_check(GL.gl_type(GL.Ptr_Buffer) === GLuint)

# Create a GL Context and window.
bp_gl_context(v2i(800, 500), "Press Enter to close me") do context::Context
    @bp_check(context === GL.get_context(),
              "Just started this Context, but another one is the singleton")

    timer::Int = 200_000
    while !GLFW.WindowShouldClose(context.window)
        clear_col = vRGBAf(rand(Float32), rand(Float32), rand(Float32), @f32 1)
        GL.render_clear(context, GL.Ptr_Target(), clear_col)

        GLFW.PollEvents()
        timer -= 1
        if (timer <= 0) || GLFW.GetKey(context.window, GLFW.KEY_ENTER)
            break
        end
    end

    # Test Buffers, initialize one with some data.
    buf::Buffer = Buffer(true, [ 0x1, 0x2, 0x3, 0x4 ])
    data::Vector{UInt8} = get_buffer_data(buf)
    @bp_check(data isa Vector{UInt8}, "Actual type: ", data)
    @bp_check(data == [ 0x1, 0x2, 0x3, 0x4 ],
              "Expected data: ", map(bitstring, [ 0x1, 0x2, 0x3, 0x4 ]),
              "\n\tActual data: ", map(bitstring, data))
    # Try setting its data after creation.
    set_buffer_data(buf, [ 0x5, 0x7, 0x9, 0x19])
    @bp_check(get_buffer_data(buf) == [ 0x5, 0x7, 0x9, 0x19 ])
    # Try reading the data into an existing array.
    buf_actual = UInt8[ 0x0, 0x0, 0x0, 0x0 ]
    get_buffer_data(buf, buf_actual)
    @bp_check(buf_actual == [ 0x5, 0x7, 0x9, 0x19 ])
    # Try setting the buffer to contain one big int, make sure there's no endianness issues.
    set_buffer_data(buf,                      [ 0b11110000000000111000001000100101 ])
    buf_actual = get_buffer_data(buf, UInt32)
    @bp_check(buf_actual == [ 0b11110000000000111000001000100101 ],
              "Actual data: ", buf_actual)
    # Try setting and getting with offsets.
    set_buffer_data(buf, [ 0x5, 0x7, 0x9, 0x19])
    buf_actual = get_buffer_data(buf, UInt8; src_elements = IntervalU(2, 2))
    @bp_check(buf_actual == [ 0x7, 0x9 ], map(bitstring, buf_actual))
    buf_actual = get_buffer_data(buf, UInt8;
                                 src_elements = IntervalU(2, 2),
                                 src_byte_offset = UInt(1))
    @bp_check(buf_actual == [ 0x9, 0x19 ], map(bitstring, buf_actual))
    buf_actual = UInt8[ 0x0, 0x0, 0x0, 0x0, 0x0, 0x0 ]
    get_buffer_data( buf, buf_actual;
                     dest_offset = UInt(1)
                   )
    @bp_check(buf_actual == [ 0x0, 0x5, 0x7, 0x9, 0x19, 0x0],
              buf_actual)
    close(buf)
end

@bp_check(isnothing(GL.get_context()),
          "Just closed the context, but it still exists")