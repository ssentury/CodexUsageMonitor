using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace CodexUsageMonitor
{
    // WPF animates the arc on its render clock; PowerShell only supplies new samples.
    public sealed class SmoothGauge : FrameworkElement
    {
        public static readonly DependencyProperty FractionProperty = DependencyProperty.Register(
            "Fraction", typeof(double), typeof(SmoothGauge),
            new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

        public double Fraction
        {
            get { return (double)GetValue(FractionProperty); }
            set { SetValue(FractionProperty, value); }
        }

        private static readonly Pen Green = MakePen(0x57, 0xD7, 0xB2);
        private static readonly Pen Yellow = MakePen(0xF4, 0xCB, 0x59);
        private static readonly Pen Red = MakePen(0xFF, 0x64, 0x6B);

        private static Pen MakePen(byte r, byte g, byte b)
        {
            var pen = new Pen(new SolidColorBrush(Color.FromRgb(r, g, b)), 12);
            pen.StartLineCap = PenLineCap.Round;
            pen.EndLineCap = PenLineCap.Round;
            pen.Freeze();
            return pen;
        }

        public void AnimateTo(double target)
        {
            target = Math.Max(0, Math.Min(1, target));
            var current = Fraction;
            var animation = new DoubleAnimation(current, target, TimeSpan.FromMilliseconds(600));
            animation.EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut };
            BeginAnimation(FractionProperty, null);
            Fraction = target;
            animation.FillBehavior = FillBehavior.Stop;
            BeginAnimation(FractionProperty, animation);
        }

        public void Reset()
        {
            BeginAnimation(FractionProperty, null);
            Fraction = 0;
        }

        protected override void OnRender(DrawingContext drawing)
        {
            base.OnRender(drawing);
            var fraction = Math.Max(0, Math.Min(1, Fraction));
            if (fraction <= 0) return;
            var angle = Math.PI * (1 - fraction);
            var end = new Point(142 + 110 * Math.Cos(angle), 114 - 110 * Math.Sin(angle));
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                context.BeginFigure(new Point(32, 114), false, false);
                context.ArcTo(end, new Size(110, 110), 0, false, SweepDirection.Clockwise, true, false);
            }
            geometry.Freeze();
            drawing.DrawGeometry(null, fraction > 0.8 ? Red : fraction > 0.6 ? Yellow : Green, geometry);
        }
    }
}
