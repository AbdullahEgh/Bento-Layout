using System.Windows.Media.Imaging;

namespace Bento.UI;

internal static class AppIcons
{
    public static ImageSource Image => BitmapFrame.Create(new Uri("pack://application:,,,/Bento;component/Assets/bento.png"));
    public static System.Drawing.Icon TrayIcon
    {
        get
        {
            using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Bento;component/Assets/bento.ico")).Stream;
            using var icon = new System.Drawing.Icon(stream, 32, 32);
            return (System.Drawing.Icon)icon.Clone();
        }
    }
}
