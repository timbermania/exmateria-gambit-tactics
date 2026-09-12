-- Extract effect texture from BIN file to TGA
-- Usage: lua extract_effect_texture.lua E001.BIN output.tga
-- Standalone version using Lua 5.4 native bitwise operators

local function read_u8(data, offset)
    return data:byte(offset + 1) or 0
end

local function read_u16(data, offset)
    local b0 = data:byte(offset + 1) or 0
    local b1 = data:byte(offset + 2) or 0
    return b0 + b1 * 256
end

local function read_u32(data, offset)
    local b0 = data:byte(offset + 1) or 0
    local b1 = data:byte(offset + 2) or 0
    local b2 = data:byte(offset + 3) or 0
    local b3 = data:byte(offset + 4) or 0
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function write_u16(value)
    return string.char(value & 0xFF, (value >> 8) & 0xFF)
end

-- BGR555 to RGBA conversion
local function bgr555_to_rgba(color16)
    local r = (color16 & 0x1F) * 8
    local g = ((color16 >> 5) & 0x1F) * 8
    local b = ((color16 >> 10) & 0x1F) * 8
    local stp = (color16 & 0x8000) ~= 0
    local a = stp and 128 or 255
    return r, g, b, a
end

-- Convert PSX texture to RGBA pixels (8bpp)
local function psx_texture_to_rgba_pixels(palette_data, width, height, pixel_data)
    local rgba_pixels = {}
    for i = 1, #pixel_data do
        local idx = pixel_data:byte(i)
        local offset = idx * 2
        local lo = palette_data:byte(offset + 1) or 0
        local hi = palette_data:byte(offset + 2) or 0
        local color16 = lo + hi * 256
        local r, g, b, a = bgr555_to_rgba(color16)
        rgba_pixels[i] = {r = r, g = g, b = b, a = a}
    end
    return rgba_pixels
end

-- Convert PSX texture to RGBA pixels (true 4bpp: 2 pixels per byte, 16-color palette)
local function psx_texture_to_rgba_pixels_4bpp(palette_data, width, height, pixel_data)
    local rgba_pixels = {}
    for i = 1, #pixel_data do
        local byte = pixel_data:byte(i)
        local idx1 = byte & 0x0F           -- low nibble = first pixel
        local idx2 = (byte >> 4) & 0x0F    -- high nibble = second pixel

        -- First pixel (palette is 16 colors × 2 bytes = 32 bytes)
        local offset1 = idx1 * 2
        local lo1 = palette_data:byte(offset1 + 1) or 0
        local hi1 = palette_data:byte(offset1 + 2) or 0
        local r1, g1, b1, a1 = bgr555_to_rgba(lo1 + hi1 * 256)
        rgba_pixels[#rgba_pixels + 1] = {r = r1, g = g1, b = b1, a = a1}

        -- Second pixel
        local offset2 = idx2 * 2
        local lo2 = palette_data:byte(offset2 + 1) or 0
        local hi2 = palette_data:byte(offset2 + 2) or 0
        local r2, g2, b2, a2 = bgr555_to_rgba(lo2 + hi2 * 256)
        rgba_pixels[#rgba_pixels + 1] = {r = r2, g = g2, b = b2, a = a2}
    end
    return rgba_pixels
end

-- Write 32-bit RGBA TGA file
local function write_rgba_tga(path, width, height, pixels)
    local parts = {}
    -- TGA Header (18 bytes)
    parts[#parts + 1] = string.char(0)      -- ID length
    parts[#parts + 1] = string.char(0)      -- Color map type
    parts[#parts + 1] = string.char(2)      -- Image type (uncompressed true-color)
    parts[#parts + 1] = string.rep("\0", 5) -- Color map spec
    parts[#parts + 1] = write_u16(0)        -- X origin
    parts[#parts + 1] = write_u16(0)        -- Y origin
    parts[#parts + 1] = write_u16(width)    -- Width
    parts[#parts + 1] = write_u16(height)   -- Height
    parts[#parts + 1] = string.char(32)     -- Bits per pixel
    parts[#parts + 1] = string.char(0x28)   -- Descriptor (top-left origin, 8 alpha bits)

    -- Pixel data (BGRA order)
    for i = 1, #pixels do
        local p = pixels[i]
        parts[#parts + 1] = string.char(p.b or 0, p.g or 0, p.r or 0, p.a or 255)
    end

    local file = io.open(path, "wb")
    if not file then
        return false, "Could not open file: " .. path
    end
    file:write(table.concat(parts))
    file:close()
    return true
end

-- Detect if effect uses 8bpp by reading first frame's flags_byte0 bit 7
local function detect_is_8bpp(data, frames_ptr)
    -- Frames section structure:
    -- byte 0: group_count
    -- bytes 1-3: padding
    -- bytes 4+: group entries (group_count * 2 bytes), then offset table, then framesets
    local group_count = read_u8(data, frames_ptr)
    if group_count == 0 then group_count = 1 end

    -- Offset table starts after group entries
    local offset_table_start = frames_ptr + 4 + (group_count * 2)

    -- First frameset offset
    local first_offset = read_u16(data, offset_table_start)

    -- Frameset data starts at frames_ptr + first_offset + 4
    -- Frameset header: 2 bytes header_flags + 2 bytes frame_count
    -- First frame starts at frameset + 4
    local frameset_start = frames_ptr + first_offset + 4
    local first_frame_offset = frameset_start + 4

    -- Read flags_byte0 of first frame
    local flags_byte0 = read_u8(data, first_frame_offset)
    local is_8bpp = (flags_byte0 & 0x80) ~= 0

    return is_8bpp
end

-- Detect CODE format and find header offset
-- CODE effects have MIPS executable code prepended before the standard header
local function find_header_offset(data)
    if #data < 40 then return 0 end

    local first_word = read_u32(data, 0x00)
    -- Check for MIPS prologue: addiu sp, sp, -N (opcode 0x27BD????)
    if (first_word & 0xFFFF0000) ~= 0x27BD0000 then
        return 0
    end

    -- Scan for embedded header (frames_ptr = 0x28)
    for offset = 4, #data - 40, 4 do
        local candidate = read_u32(data, offset)
        if candidate == 0x28 then
            -- Verify ascending pointers within file bounds
            local valid = true
            local ptrs = {}
            for i = 0, 9 do
                local ptr = read_u32(data, offset + i * 4)
                if offset + ptr > #data then
                    valid = false
                    break
                end
                ptrs[i] = ptr
            end
            if valid then
                -- Check non-decreasing (skip time_scale_ptr at index 5)
                local check = {ptrs[0], ptrs[1], ptrs[2], ptrs[3], ptrs[4], ptrs[6], ptrs[7], ptrs[8], ptrs[9]}
                local ascending = true
                for i = 2, #check do
                    if check[i] < check[i-1] then
                        ascending = false
                        break
                    end
                end
                if ascending then return offset end
            end
        end
    end
    return 0
end

local function extract_texture(bin_path, output_path, header_offset)
    local file = io.open(bin_path, "rb")
    if not file then error("Cannot open " .. bin_path) end
    local data = file:read("*all")
    file:close()

    -- Use provided offset or detect automatically
    local base = header_offset or find_header_offset(data)

    local frames_ptr = base + read_u32(data, base + 0x00)
    local texture_ptr = base + read_u32(data, base + 0x24)

    -- Detect color depth from first frame's flags
    local is_8bpp = detect_is_8bpp(data, frames_ptr)

    -- Read image size data from texture_ptr + 0x400
    -- Shishi's method:
    -- imageSizeData[3] != 0 -> rowBytes=256, height = value >> 8
    -- imageSizeData[3] == 0 -> rowBytes=128, height = value >> 7
    local size_data_0 = read_u8(data, texture_ptr + 0x400)
    local size_data_1 = read_u8(data, texture_ptr + 0x401)
    local size_data_3 = read_u8(data, texture_ptr + 0x403)

    local combined_value = size_data_0 + size_data_1 * 256
    local row_bytes, shift
    if size_data_3 ~= 0 then
        row_bytes = 256
        shift = 8
    else
        row_bytes = 128
        shift = 7
    end
    local height = combined_value >> shift

    -- Fallback: if size data gives height=0, calculate from section size
    -- This happens with CODE format effects where size data bytes may be zero
    if height == 0 then
        local pixel_data_size = #data - (texture_ptr + 0x404)
        if pixel_data_size > 0 then
            if is_8bpp then
                row_bytes = 256
                height = pixel_data_size // row_bytes
            else
                row_bytes = 128
                height = pixel_data_size // row_bytes
            end
        end
    end

    -- Calculate width and byte count based on color depth
    local width, byte_count
    if is_8bpp then
        width = row_bytes
        byte_count = width * height
    else
        -- 4bpp: 2 pixels per byte
        width = row_bytes * 2
        byte_count = (width * height) // 2
    end

    -- Palette location differs for 4bpp vs 8bpp
    local palette_data
    if is_8bpp then
        -- 8bpp: 256 colors at offset 0x000 (512 bytes)
        palette_data = data:sub(texture_ptr + 1, texture_ptr + 512)
    else
        -- 4bpp: 16 colors at offset 0x200 (32 bytes)
        palette_data = data:sub(texture_ptr + 0x201, texture_ptr + 0x220)
    end

    -- Pixel data starts at texture_ptr + 0x404
    local pixels = data:sub(texture_ptr + 0x405, texture_ptr + 0x404 + byte_count)

    local rgba_pixels
    if is_8bpp then
        rgba_pixels = psx_texture_to_rgba_pixels(palette_data, width, height, pixels)
    else
        rgba_pixels = psx_texture_to_rgba_pixels_4bpp(palette_data, width, height, pixels)
    end

    write_rgba_tga(output_path, width, height, rgba_pixels)
    print(string.format("%dx%d (%s) -> %s", width, height, is_8bpp and "8bpp" or "4bpp", output_path))
end

if #arg < 2 then
    print("Usage: lua extract_effect_texture.lua input.BIN output.tga [header_offset]")
    os.exit(1)
end

local header_offset = arg[3] and tonumber(arg[3]) or nil
extract_texture(arg[1], arg[2], header_offset)
