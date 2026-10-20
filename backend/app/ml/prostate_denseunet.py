"""3D multi-branch Dense U-Net, copied from the training notebook (03b_Segmentation_dense_unet).

Branch 1: T2W (1 channel). Branch 2: ADC + DWI/HBV (2 channels, ADC first). Fused at the bottleneck;
the decoder uses skip connections from the T2W branch only. Output: 1-channel logits (lesion).
Keep the layer names: they must match the saved `state_dict`.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


class DenseLayer3D(nn.Module):
    def __init__(self, in_channels, growth_rate):
        super().__init__()
        self.norm = nn.BatchNorm3d(in_channels)
        self.relu = nn.ReLU(inplace=True)
        self.conv = nn.Conv3d(in_channels, growth_rate, kernel_size=3, padding=1, bias=False)

    def forward(self, x):
        return torch.cat([x, self.conv(self.relu(self.norm(x)))], dim=1)


class DenseBlock3D(nn.Module):
    def __init__(self, in_channels, growth_rate, num_layers):
        super().__init__()
        layers, channels = [], in_channels
        for _ in range(num_layers):
            layers.append(DenseLayer3D(channels, growth_rate))
            channels += growth_rate
        self.block = nn.Sequential(*layers)
        self.out_channels = channels

    def forward(self, x):
        return self.block(x)


class TransitionDown3D(nn.Module):
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.transition = nn.Sequential(
            nn.BatchNorm3d(in_channels),
            nn.ReLU(inplace=True),
            nn.Conv3d(in_channels, out_channels, kernel_size=1, bias=False),
            nn.MaxPool3d(kernel_size=2, stride=2),
        )

    def forward(self, x):
        return self.transition(x)


class TransitionUp3D(nn.Module):
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.up = nn.ConvTranspose3d(in_channels, out_channels, kernel_size=2, stride=2)

    def forward(self, x, target_size):
        x = self.up(x)
        if x.shape[2:] != target_size:
            x = F.interpolate(x, size=target_size, mode="trilinear", align_corners=False)
        return x


class MultiBranchDenseUNet3D(nn.Module):
    def __init__(self, out_classes=1, growth_rate=12, num_layers=3):
        super().__init__()
        g, n = growth_rate, num_layers

        self.t2_stem = nn.Conv3d(1, 16, kernel_size=3, padding=1)
        self.t2_dense1 = DenseBlock3D(16, g, n)
        self.t2_down1 = TransitionDown3D(self.t2_dense1.out_channels, 32)
        self.t2_dense2 = DenseBlock3D(32, g, n)
        self.t2_down2 = TransitionDown3D(self.t2_dense2.out_channels, 64)
        self.t2_dense3 = DenseBlock3D(64, g, n)
        self.t2_down3 = TransitionDown3D(self.t2_dense3.out_channels, 96)

        self.dw_stem = nn.Conv3d(2, 16, kernel_size=3, padding=1)
        self.dw_dense1 = DenseBlock3D(16, g, n)
        self.dw_down1 = TransitionDown3D(self.dw_dense1.out_channels, 32)
        self.dw_dense2 = DenseBlock3D(32, g, n)
        self.dw_down2 = TransitionDown3D(self.dw_dense2.out_channels, 64)
        self.dw_dense3 = DenseBlock3D(64, g, n)

        self.bottleneck = DenseBlock3D(96 + self.dw_dense3.out_channels, g, n)

        self.up3 = TransitionUp3D(self.bottleneck.out_channels, 64)
        self.dec3 = DenseBlock3D(64 + self.t2_dense3.out_channels, g, n)
        self.up2 = TransitionUp3D(self.dec3.out_channels, 32)
        self.dec2 = DenseBlock3D(32 + self.t2_dense2.out_channels, g, n)
        self.up1 = TransitionUp3D(self.dec2.out_channels, 16)
        self.dec1 = DenseBlock3D(16 + self.t2_dense1.out_channels, g, n)
        self.out_conv = nn.Conv3d(self.dec1.out_channels, out_classes, kernel_size=1)

    def forward(self, t2w_x, adc_dwi_x):
        t2_1 = self.t2_dense1(self.t2_stem(t2w_x))
        t2_2 = self.t2_dense2(self.t2_down1(t2_1))
        t2_3 = self.t2_dense3(self.t2_down2(t2_2))
        t2_b = self.t2_down3(t2_3)

        dw_1 = self.dw_dense1(self.dw_stem(adc_dwi_x))
        dw_2 = self.dw_dense2(self.dw_down1(dw_1))
        dw_3 = self.dw_dense3(self.dw_down2(dw_2))

        # ADC/DWI arrive at a different in-plane size than T2W: fuse in T2W bottleneck space.
        dw_3 = F.interpolate(dw_3, size=t2_b.shape[2:], mode="trilinear", align_corners=False)
        x = self.bottleneck(torch.cat([t2_b, dw_3], dim=1))

        x = self.dec3(torch.cat([self.up3(x, t2_3.shape[2:]), t2_3], dim=1))
        x = self.dec2(torch.cat([self.up2(x, t2_2.shape[2:]), t2_2], dim=1))
        x = self.dec1(torch.cat([self.up1(x, t2_1.shape[2:]), t2_1], dim=1))
        return self.out_conv(x)


def load_model(weights_path) -> MultiBranchDenseUNet3D:
    model = MultiBranchDenseUNet3D(out_classes=1)
    # weights_only=True: the file is a pickle; never execute code from it.
    model.load_state_dict(torch.load(weights_path, map_location="cpu", weights_only=True), strict=True)
    return model.eval()
