
#ifndef FRAMEBUFFER_FLAT_HLSL
#define FRAMEBUFFER_FLAT_HLSL

// ��R16G16B16A16_UNORM���Ϊfloat4
float4 UnpackRGBA16(uint2 e)
{
    return float4(f16tof32(e), f16tof32(e >> 16));
}

// ��float4���ΪR16G16B16A16_UNORM
uint2 PackRGBA16(float4 c)
{
    return f32tof16(c.rg) | (f32tof16(c.ba) << 16);
}

// ���ݸ�����2D��ַ�Ͳ���������λ�����ǵ�1D֡��������
uint GetFramebufferSampleAddress(uint2 coords, uint sampleIndex)
{
    // ������: Row (x), Col (y), MSAA sample
    return (sampleIndex * g_FramebufferDimensions.y + coords.y) * g_FramebufferDimensions.x + coords.x;
}

#endif // FRAMEBUFFER_FLAT_HLSL
