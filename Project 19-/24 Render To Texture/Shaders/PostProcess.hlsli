
Texture2D g_Tex : register(t0);
SamplerState g_Sam : register(s0);

cbuffer CB : register(b0)
{
    float g_VisibleRange;        // 3D������ӷ�Χ
    float3 g_EyePosW;            // �����λ�� 
    float4 g_RectW;              // С��ͼxOzƽ���Ӧ3D�����������(Left, Front, Right, Back)
}

struct VertexPosHTex
{
    float4 PosH : SV_POSITION;
    float2 Tex : TEXCOORD;
};

