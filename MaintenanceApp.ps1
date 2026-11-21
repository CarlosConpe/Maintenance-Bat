param(
    [switch]$SelfTest,
    [string]$InvokedBy
)

# ============================================================================
#  Maintenance Tool - interfaz gráfica (WPF, Windows PowerShell 5.1)
#  Toda la lógica de limpieza vive en Maintenance.ps1; esta ventana solo la
#  muestra, la configura y la lanza en un proceso aparte.
# ============================================================================

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$script:AppDir = $PSScriptRoot
$script:Engine = Join-Path $script:AppDir 'Maintenance.ps1'
if (-not (Test-Path -LiteralPath $script:Engine)) {
    [System.Windows.MessageBox]::Show("Falta Maintenance.ps1 en:`n$script:AppDir", 'Maintenance Tool', 'OK', 'Error') | Out-Null
    exit 1
}
. $script:Engine

$ErrorActionPreference = 'Continue'
$script:IsAdmin = Test-IsAdmin
$script:LogRoot = Get-DefaultLogRoot
$script:HistoryRoots = @($script:LogRoot, (Get-LegacyLogRoot))
$script:Proc = $null
$script:Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:Readers = @()
$script:Pool = $null
$script:RunRows = @()
$script:RunTotal = 0
$script:RunDone = 0
$script:RunEnd = $null
$script:RunWarnings = @()
$script:EofCount = 0
$script:LastLogDir = $null

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Maintenance Tool" Width="1120" Height="740" MinWidth="900" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource AppBg}" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <SolidColorBrush x:Key="AppBg" Color="#F3F4F6"/>
    <SolidColorBrush x:Key="CardBg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="InputBg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Fg" Color="#111827"/>
    <SolidColorBrush x:Key="Muted" Color="#6B7280"/>
    <SolidColorBrush x:Key="Line" Color="#E5E7EB"/>
    <SolidColorBrush x:Key="Line2" Color="#D1D5DB"/>
    <SolidColorBrush x:Key="Hover" Color="#DBEAFE"/>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource InputBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Line2}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource Fg}"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="{DynamicResource Hover}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Nav" TargetType="Button">
      <Setter Property="Foreground" Value="#D1D5DB"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height" Value="42"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Padding" Value="22,0,0,0"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Foreground" Value="White"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Line2}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#2563EB"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#2563EB"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="#DC2626"/>
      <Setter Property="BorderBrush" Value="#F87171"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="24"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="0,0,0,16"/>
    </Style>
    <Style x:Key="H2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="18"/>
      <Setter Property="Margin" Value="0,0,0,14"/>
    </Style>
    <Style TargetType="DataGrid">
      <Setter Property="AutoGenerateColumns" Value="False"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="SelectionMode" Value="Single"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource Line}"/>
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="RowBackground" Value="{DynamicResource CardBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
      <Setter Property="RowHeight" Value="30"/>
      <Setter Property="CanUserAddRows" Value="False"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="220"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Barra lateral -->
    <Grid Background="#111827">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Margin="22,26,16,26">
        <TextBlock Text="Maintenance" Foreground="White" FontSize="20" FontWeight="Bold"/>
        <TextBlock x:Name="TxtVersion" Text="Tool" Foreground="#60A5FA" FontSize="13"/>
      </StackPanel>
      <StackPanel Grid.Row="1" x:Name="NavPanel">
        <Button x:Name="NavHome" Style="{StaticResource Nav}" Tag="PageHome" Content="Inicio"/>
        <Button x:Name="NavMaint" Style="{StaticResource Nav}" Tag="PageMaint" Content="Mantenimiento"/>
        <Button x:Name="NavStartup" Style="{StaticResource Nav}" Tag="PageStartup" Content="Arranque de Windows"/>
        <Button x:Name="NavSchedule" Style="{StaticResource Nav}" Tag="PageSchedule" Content="Tareas programadas"/>
        <Button x:Name="NavSpace" Style="{StaticResource Nav}" Tag="PageSpace" Content="Espacio en disco"/>
        <Button x:Name="NavPerf" Style="{StaticResource Nav}" Tag="PagePerf" Content="Rendimiento"/>
        <Button x:Name="NavHistory" Style="{StaticResource Nav}" Tag="PageHistory" Content="Historial"/>
        <Button x:Name="NavTools" Style="{StaticResource Nav}" Tag="PageTools" Content="Herramientas"/>
      </StackPanel>
      <StackPanel Grid.Row="2" Margin="22,0,16,20">
        <Button x:Name="BtnTheme" Style="{StaticResource Nav}" Padding="0" Height="30" FontSize="12" Margin="0,0,0,10" Content="Tema: automático"/>
        <TextBlock x:Name="TxtAdmin" Foreground="#9CA3AF" FontSize="11" TextWrapping="Wrap"/>
        <TextBlock x:Name="TxtUser" Foreground="#6B7280" FontSize="11" TextWrapping="Wrap" Margin="0,4,0,0"/>
      </StackPanel>
    </Grid>

    <!-- Contenido -->
    <Grid Grid.Column="1" Margin="30,26,30,20">

      <!-- INICIO -->
      <ScrollViewer x:Name="PageHome" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Estado del equipo"/>
          <TextBlock Style="{StaticResource Sub}" x:Name="TxtHomeSub" Text="Resumen rápido. No se modifica nada al abrir esta pantalla."/>
          <Border x:Name="BannerUser" Background="#FEF3C7" CornerRadius="8" Padding="14" Margin="0,0,0,14" Visibility="Collapsed">
            <TextBlock x:Name="TxtBannerUser" TextWrapping="Wrap" Foreground="#92400E"/>
          </Border>
          <Border x:Name="BannerUpdate" Background="#DBEAFE" CornerRadius="8" Padding="14" Margin="0,0,0,14" Visibility="Collapsed">
            <DockPanel>
              <Button x:Name="BtnUpdateOpen" DockPanel.Dock="Right" Style="{StaticResource Primary}" Margin="10,0,0,0" Content="Descargar"/>
              <TextBlock x:Name="TxtBannerUpdate" TextWrapping="Wrap" Foreground="#1E3A8A" VerticalAlignment="Center"/>
            </DockPanel>
          </Border>
          <WrapPanel x:Name="HomeCards"/>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Avisos"/>
              <StackPanel x:Name="HomeAlerts"/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Acciones rápidas"/>
              <WrapPanel>
                <Button x:Name="BtnHomeQuick" Style="{StaticResource Primary}" Content="Limpieza rápida (2-5 min)"/>
                <Button x:Name="BtnHomeFull" Style="{StaticResource Btn}" Content="Mantenimiento completo"/>
                <Button x:Name="BtnHomeSim" Style="{StaticResource Btn}" Content="Simular (no cambia nada)"/>
                <Button x:Name="BtnHomeRefresh" Style="{StaticResource Btn}" Content="Actualizar"/>
              </WrapPanel>
              <TextBlock Foreground="{DynamicResource Muted}" TextWrapping="Wrap" FontSize="12"
                         Text="Limpieza rápida: temporales antiguos, caché de navegadores y DNS. Completo: añade punto de restauración, liberador de espacio, reparación de Windows (30-60 min), Windows Update y optimización de la unidad."/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <!-- MANTENIMIENTO -->
      <Grid x:Name="PageMaint" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Mantenimiento"/>
          <TextBlock Style="{StaticResource Sub}" Text="Elige los pasos y pulsa Ejecutar. Con 'Simulación' solo se mide lo que se haría."/>
        </StackPanel>
        <Grid Grid.Row="1">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="330"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}" Margin="0,0,14,0">
            <DockPanel>
              <StackPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <TextBlock Text="Temporales con más de" VerticalAlignment="Center"/>
                  <TextBox x:Name="TxtTempDays" Width="40" Margin="6,0" Text="7" VerticalContentAlignment="Center" Padding="3"/>
                  <TextBlock Text="días" VerticalAlignment="Center"/>
                </StackPanel>
                <CheckBox x:Name="ChkSimulate" Content="Simulación (no cambia nada)" Margin="0,0,0,10"/>
                <WrapPanel>
                  <Button x:Name="BtnRun" Style="{StaticResource Primary}" Content="Ejecutar"/>
                  <Button x:Name="BtnCancel" Style="{StaticResource Danger}" Content="Cancelar" IsEnabled="False"/>
                </WrapPanel>
              </StackPanel>
              <StackPanel DockPanel.Dock="Top">
                <TextBlock Style="{StaticResource H2}" Text="Pasos"/>
                <WrapPanel Margin="0,0,0,6">
                  <Button x:Name="BtnSelQuick" Style="{StaticResource Btn}" Padding="8,3" Content="Rápido"/>
                  <Button x:Name="BtnSelRec" Style="{StaticResource Btn}" Padding="8,3" Content="Recomendado"/>
                  <Button x:Name="BtnSelNone" Style="{StaticResource Btn}" Padding="8,3" Content="Ninguno"/>
                </WrapPanel>
              </StackPanel>
              <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="MaintSteps"/>
              </ScrollViewer>
            </DockPanel>
          </Border>
          <Grid Grid.Column="1">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel Margin="0,0,0,10">
              <TextBlock x:Name="TxtCurrent" Text="Listo." FontWeight="SemiBold" Margin="0,0,0,6"/>
              <ProgressBar x:Name="Progress" Height="8" Minimum="0" Maximum="1" Value="0" Foreground="#2563EB" Background="{DynamicResource Line}" BorderThickness="0"/>
              <TextBlock x:Name="TxtProgressDetail" Foreground="{DynamicResource Muted}" FontSize="11" Margin="0,4,0,0"/>
            </StackPanel>
            <DataGrid Grid.Row="1" x:Name="GridRun" MaxHeight="230" Margin="0,0,0,10">
              <DataGrid.Columns>
                <DataGridTextColumn Header="Paso" Binding="{Binding Paso}" Width="2*"/>
                <DataGridTextColumn Header="Estado" Binding="{Binding Estado}" Width="90"/>
                <DataGridTextColumn Header="Tiempo" Binding="{Binding Tiempo}" Width="70"/>
                <DataGridTextColumn Header="Detalle" Binding="{Binding Detalle}" Width="2*"/>
              </DataGrid.Columns>
            </DataGrid>
            <TextBox Grid.Row="2" x:Name="TxtLog" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"
                     Background="#0F172A" Foreground="#E2E8F0" BorderThickness="0" Padding="10"/>
            <DockPanel Grid.Row="3" Margin="0,10,0,0">
              <Button x:Name="BtnOpenLog" DockPanel.Dock="Right" Style="{StaticResource Btn}" Margin="0" Content="Abrir registros" IsEnabled="False"/>
              <TextBlock x:Name="TxtSummary" TextWrapping="Wrap" VerticalAlignment="Center"/>
            </DockPanel>
          </Grid>
        </Grid>
      </Grid>

      <!-- ARRANQUE -->
      <Grid x:Name="PageStartup" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Arranque de Windows"/>
          <TextBlock Style="{StaticResource Sub}" Text="Programas que se abren al iniciar sesión. Desactivar los que no necesitas acelera el arranque. No se borra nada: es el mismo interruptor que el Administrador de tareas y se puede volver a activar."/>
        </StackPanel>
        <WrapPanel Grid.Row="1">
          <Button x:Name="BtnStartupDisable" Style="{StaticResource Primary}" Content="Desactivar seleccionado"/>
          <Button x:Name="BtnStartupEnable" Style="{StaticResource Btn}" Content="Activar seleccionado"/>
          <Button x:Name="BtnStartupRefresh" Style="{StaticResource Btn}" Content="Actualizar"/>
          <TextBlock x:Name="TxtStartupInfo" VerticalAlignment="Center" Foreground="{DynamicResource Muted}" Margin="6,0,0,8"/>
        </WrapPanel>
        <DataGrid Grid.Row="2" x:Name="GridStartup">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Programa" Binding="{Binding Nombre}" Width="2*"/>
            <DataGridTextColumn Header="Estado" Binding="{Binding Estado}" Width="100"/>
            <DataGridTextColumn Header="Origen" Binding="{Binding Origen}" Width="130"/>
            <DataGridTextColumn Header="Comando" Binding="{Binding Comando}" Width="4*"/>
          </DataGrid.Columns>
        </DataGrid>
      </Grid>

      <!-- TAREAS PROGRAMADAS -->
      <Grid x:Name="PageSchedule" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Tareas programadas"/>
          <TextBlock Style="{StaticResource Sub}" Text="Mantenimiento recurrente que Windows ejecuta solo, en segundo plano, mientras tu sesión está iniciada. Si el equipo estaba apagado, se ejecuta en cuanto se pueda."/>
        </StackPanel>
        <Grid Grid.Row="1">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="320"/>
          </Grid.ColumnDefinitions>
          <DockPanel Margin="0,0,14,0">
            <WrapPanel DockPanel.Dock="Top">
              <Button x:Name="BtnSchRunNow" Style="{StaticResource Btn}" Content="Ejecutar ahora"/>
              <Button x:Name="BtnSchToggle" Style="{StaticResource Btn}" Content="Pausar / reanudar"/>
              <Button x:Name="BtnSchDelete" Style="{StaticResource Danger}" Content="Eliminar"/>
              <Button x:Name="BtnSchRefresh" Style="{StaticResource Btn}" Content="Actualizar"/>
            </WrapPanel>
            <DataGrid x:Name="GridSchedules">
              <DataGrid.Columns>
                <DataGridTextColumn Header="Nombre" Binding="{Binding Nombre}" Width="*"/>
                <DataGridTextColumn Header="Cuándo" Binding="{Binding Cuando}" Width="1.4*"/>
                <DataGridTextColumn Header="Estado" Binding="{Binding Estado}" Width="80"/>
                <DataGridTextColumn Header="Próxima" Binding="{Binding Proxima}" Width="120"/>
                <DataGridTextColumn Header="Última" Binding="{Binding Ultima}" Width="120"/>
                <DataGridTextColumn Header="Pasos" Binding="{Binding Pasos}" Width="1.6*"/>
              </DataGrid.Columns>
            </DataGrid>
          </DockPanel>
          <Border Grid.Column="1" Style="{StaticResource Card}" Margin="0">
            <DockPanel>
              <StackPanel DockPanel.Dock="Top">
                <TextBlock Style="{StaticResource H2}" Text="Nueva tarea"/>
                <TextBlock Text="Nombre" Foreground="{DynamicResource Muted}"/>
                <TextBox x:Name="TxtSchName" Text="Limpieza semanal" Padding="4" Margin="0,2,0,8"/>
                <TextBlock Text="Frecuencia" Foreground="{DynamicResource Muted}"/>
                <ComboBox x:Name="CmbSchFreq" Margin="0,2,0,8"/>
                <TextBlock Text="Día" Foreground="{DynamicResource Muted}"/>
                <ComboBox x:Name="CmbSchDay" Margin="0,2,0,8"/>
                <TextBlock Text="Hora (HH:mm)" Foreground="{DynamicResource Muted}"/>
                <TextBox x:Name="TxtSchTime" Text="13:00" Padding="4" Margin="0,2,0,8"/>
                <TextBlock Text="Pasos" Foreground="{DynamicResource Muted}" Margin="0,0,0,4"/>
              </StackPanel>
              <WrapPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
                <Button x:Name="BtnSchCreate" Style="{StaticResource Primary}" Content="Crear tarea"/>
                <Button x:Name="BtnSchPreset" Style="{StaticResource Btn}" Content="Plantilla rápida"/>
              </WrapPanel>
              <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="SchSteps"/>
              </ScrollViewer>
            </DockPanel>
          </Border>
        </Grid>
      </Grid>

      <!-- ESPACIO -->
      <Grid x:Name="PageSpace" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Espacio en disco"/>
          <TextBlock Style="{StaticResource Sub}" Text="Muestra qué carpetas y archivos ocupan más. Solo lectura: no borra nada. Doble clic en una fila para abrirla en el Explorador y decidir tú qué hacer."/>
        </StackPanel>
        <DockPanel Grid.Row="1" Margin="0,0,0,6">
          <Button x:Name="BtnSpaceRun" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="Analizar"/>
          <Button x:Name="BtnSpaceCancel" DockPanel.Dock="Right" Style="{StaticResource Danger}" Content="Cancelar" IsEnabled="False"/>
          <Button x:Name="BtnSpaceBrowse" DockPanel.Dock="Right" Style="{StaticResource Btn}" Content="Examinar..."/>
          <TextBox x:Name="TxtSpacePath" Padding="6" Margin="0,0,8,8" VerticalContentAlignment="Center"/>
        </DockPanel>
        <WrapPanel Grid.Row="2">
          <Button x:Name="BtnSpaceUser" Style="{StaticResource Btn}" Padding="8,3" Content="Mi carpeta de usuario"/>
          <Button x:Name="BtnSpaceDownloads" Style="{StaticResource Btn}" Padding="8,3" Content="Descargas"/>
          <Button x:Name="BtnSpaceDrive" Style="{StaticResource Btn}" Padding="8,3" Content="Unidad del sistema"/>
          <TextBlock x:Name="TxtSpaceStatus" VerticalAlignment="Center" Foreground="{DynamicResource Muted}" Margin="8,0,0,8"/>
        </WrapPanel>
        <Grid Grid.Row="3">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <DockPanel Margin="0,0,14,0">
            <TextBlock DockPanel.Dock="Top" Style="{StaticResource H2}" Text="Carpetas"/>
            <DataGrid x:Name="GridSpaceFolders">
              <DataGrid.Columns>
                <DataGridTextColumn Header="Carpeta" Binding="{Binding Nombre}" Width="2*"/>
                <DataGridTextColumn Header="Tamaño" Binding="{Binding Tamano}" Width="90"/>
                <DataGridTextColumn Header="%" Binding="{Binding Porcentaje}" Width="55"/>
                <DataGridTextColumn Header="Archivos" Binding="{Binding Archivos}" Width="80"/>
              </DataGrid.Columns>
            </DataGrid>
          </DockPanel>
          <DockPanel Grid.Column="1">
            <TextBlock DockPanel.Dock="Top" Style="{StaticResource H2}" Text="Archivos más grandes"/>
            <DataGrid x:Name="GridSpaceFiles">
              <DataGrid.Columns>
                <DataGridTextColumn Header="Archivo" Binding="{Binding Nombre}" Width="2*"/>
                <DataGridTextColumn Header="Tamaño" Binding="{Binding Tamano}" Width="90"/>
                <DataGridTextColumn Header="Modificado" Binding="{Binding Modificado}" Width="90"/>
                <DataGridTextColumn Header="Carpeta" Binding="{Binding Carpeta}" Width="2*"/>
              </DataGrid.Columns>
            </DataGrid>
          </DockPanel>
        </Grid>
      </Grid>

      <!-- RENDIMIENTO -->
      <Grid x:Name="PagePerf" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Rendimiento"/>
          <TextBlock Style="{StaticResource Sub}" Text="Programas que más consumen ahora mismo. Se actualiza cada 2 segundos mientras esta pantalla está abierta. Solo lectura."/>
        </StackPanel>
        <WrapPanel Grid.Row="1" x:Name="PerfCards"/>
        <WrapPanel Grid.Row="2">
          <TextBlock Text="Ordenar por:" VerticalAlignment="Center" Margin="0,0,8,8"/>
          <RadioButton x:Name="RbPerfCpu" Content="CPU" IsChecked="True" Margin="0,0,12,8" VerticalAlignment="Center" Foreground="{DynamicResource Fg}"/>
          <RadioButton x:Name="RbPerfMem" Content="Memoria" Margin="0,0,20,8" VerticalAlignment="Center" Foreground="{DynamicResource Fg}"/>
          <Button x:Name="BtnPerfTaskmgr" Style="{StaticResource Btn}" Content="Abrir Administrador de tareas"/>
        </WrapPanel>
        <DataGrid Grid.Row="3" x:Name="GridPerf">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Programa" Binding="{Binding Nombre}" Width="2*"/>
            <DataGridTextColumn Header="CPU %" Binding="{Binding Cpu}" Width="80"/>
            <DataGridTextColumn Header="Memoria" Binding="{Binding Memoria}" Width="100"/>
            <DataGridTextColumn Header="PID" Binding="{Binding Id}" Width="80"/>
          </DataGrid.Columns>
        </DataGrid>
      </Grid>

      <!-- HISTORIAL -->
      <Grid x:Name="PageHistory" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Historial"/>
          <TextBlock Style="{StaticResource Sub}" x:Name="TxtHistorySub"/>
        </StackPanel>
        <WrapPanel Grid.Row="1">
          <Button x:Name="BtnHistOpen" Style="{StaticResource Btn}" Content="Abrir carpeta"/>
          <Button x:Name="BtnHistRefresh" Style="{StaticResource Btn}" Content="Actualizar"/>
        </WrapPanel>
        <Grid Grid.Row="2">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="260"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <DataGrid x:Name="GridHistory" Margin="0,0,14,0">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Fecha" Binding="{Binding Fecha}" Width="*"/>
              <DataGridTextColumn Header="Modo" Binding="{Binding Modo}" Width="90"/>
            </DataGrid.Columns>
          </DataGrid>
          <TextBox Grid.Column="1" x:Name="TxtHistoryLog" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                   VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"
                   BorderBrush="{DynamicResource Line}" Padding="10"/>
        </Grid>
      </Grid>

      <!-- HERRAMIENTAS -->
      <ScrollViewer x:Name="PageTools" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <TextBlock Style="{StaticResource H1}" Text="Herramientas"/>
          <TextBlock Style="{StaticResource Sub}" Text="Accesos directos a las herramientas de Windows más útiles para revisar y acelerar el equipo."/>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Plan de energía"/>
              <TextBlock x:Name="TxtPowerPlan" Margin="0,0,0,10"/>
              <WrapPanel>
                <Button x:Name="BtnPowerBalanced" Style="{StaticResource Btn}" Content="Equilibrado"/>
                <Button x:Name="BtnPowerHigh" Style="{StaticResource Btn}" Content="Alto rendimiento"/>
                <Button x:Name="BtnPowerSettings" Style="{StaticResource Btn}" Content="Opciones de energía"/>
              </WrapPanel>
              <TextBlock Foreground="#6B7280" FontSize="12" TextWrapping="Wrap"
                         Text="Alto rendimiento acelera el equipo a cambio de más consumo. En portátiles con batería se recomienda Equilibrado."/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Esta aplicación"/>
              <WrapPanel>
                <Button x:Name="BtnShortcut" Style="{StaticResource Primary}" Content="Crear acceso directo (Escritorio y menú Inicio)"/>
                <Button x:Name="BtnLogFolder" Style="{StaticResource Btn}" Content="Carpeta de registros"/>
                <Button x:Name="BtnCheckUpdate" Style="{StaticResource Btn}" Content="Buscar actualizaciones"/>
                <Button x:Name="BtnUninstall" Style="{StaticResource Danger}" Content="Desinstalar..."/>
              </WrapPanel>
              <CheckBox x:Name="ChkAutoUpdate" Content="Comprobar si hay versión nueva al abrir (consulta GitHub, no envía datos del equipo)" Margin="0,0,0,8"/>
              <TextBlock x:Name="TxtAppInfo" Foreground="{DynamicResource Muted}" FontSize="12" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Windows"/>
              <WrapPanel x:Name="ToolsPanel"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$ui = @{}
foreach ($n in $xaml.SelectNodes('//*[@*[local-name()="Name"]][not(ancestor::*[local-name()="ControlTemplate"])]')) {
    $name = $n.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1 -ExpandProperty Value
    $ui[$name] = $window.FindName($name)
}

# ----------------------------------------------------------------------------
#  Utilidades de interfaz
# ----------------------------------------------------------------------------

$script:Brush = @{
    Ok = '#16A34A'; Warn = '#D97706'; Bad = '#DC2626'; Info = '#2563EB'; Muted = '#6B7280'
}

$script:Pages = @('PageHome', 'PageMaint', 'PageStartup', 'PageSchedule', 'PageSpace', 'PagePerf', 'PageHistory', 'PageTools')
function Get-ThemeBrush([string]$Key) { return $window.Resources[$Key] }

function New-Brush([string]$Hex) { return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex) }

function Show-Info([string]$Text) { [System.Windows.MessageBox]::Show($window, $Text, 'Maintenance Tool', 'OK', 'Information') | Out-Null }
function Show-Error([string]$Text) { [System.Windows.MessageBox]::Show($window, $Text, 'Maintenance Tool', 'OK', 'Error') | Out-Null }
function Confirm-Action([string]$Text) {
    return ([System.Windows.MessageBox]::Show($window, $Text, 'Maintenance Tool', 'YesNo', 'Question') -eq 'Yes')
}

function Invoke-Safe([scriptblock]$Block) {
    try { & $Block } catch { Show-Error $_.Exception.Message }
}

function Show-Page([string]$Name) {
    foreach ($p in $script:Pages) {
        $ui[$p].Visibility = $(if ($p -eq $Name) { 'Visible' } else { 'Collapsed' })
    }
    foreach ($b in $ui.NavPanel.Children) {
        if ($b.Tag -eq $Name) { $b.Background = New-Brush '#1F2937'; $b.Foreground = New-Brush '#FFFFFF' }
        else { $b.Background = [System.Windows.Media.Brushes]::Transparent; $b.Foreground = New-Brush '#D1D5DB' }
    }
    switch ($Name) {
        'PageStartup' { Invoke-Safe { Update-Startup } }
        'PageSchedule' { Invoke-Safe { Update-Schedules } }
        'PageHistory' { Invoke-Safe { Update-History } }
        'PageTools' { Update-PowerPlan }
        'PageSpace' { if (-not $ui.TxtSpacePath.Text) { $ui.TxtSpacePath.Text = $script:Settings.SpacePath } }
    }
    if ($Name -eq 'PagePerf') { Update-Perf; if (-not $SelfTest) { $script:PerfTimer.Start() } } else { $script:PerfTimer.Stop() }
}

function New-Card([string]$Title, [string]$Value, [string]$Sub, [string]$Color) {
    $b = New-Object System.Windows.Controls.Border
    $b.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'CardBg')
    $b.CornerRadius = 10
    $b.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'Line')
    $b.BorderThickness = 1
    $b.Padding = 16
    $b.Margin = '0,0,14,14'
    $b.Width = 200
    $sp = New-Object System.Windows.Controls.StackPanel
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Title; $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Muted'); $t.FontSize = 12
    $v = New-Object System.Windows.Controls.TextBlock
    $v.Text = $Value; $v.FontSize = 22; $v.FontWeight = 'SemiBold'; $v.Foreground = New-Brush $Color; $v.Margin = '0,4,0,2'
    $s = New-Object System.Windows.Controls.TextBlock
    $s.Text = $Sub; $s.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Muted'); $s.FontSize = 11; $s.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($t); [void]$sp.Children.Add($v); [void]$sp.Children.Add($s)
    $b.Child = $sp
    return $b
}

function Add-Alert([string]$Text, [string]$Color) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = [char]0x25CF + '  ' + $Text
    $t.Foreground = New-Brush $Color
    $t.TextWrapping = 'Wrap'
    $t.Margin = '0,0,0,6'
    [void]$ui.HomeAlerts.Children.Add($t)
}

function New-StepChecks($Panel, [string[]]$Checked) {
    $Panel.Children.Clear()
    foreach ($s in (Get-StepList)) {
        $c = New-Object System.Windows.Controls.CheckBox
        $c.Content = $s.Title
        $c.Tag = $s.Key
        $c.Margin = '0,3,0,3'
        $c.IsChecked = ($Checked -contains $s.Key)
        [void]$Panel.Children.Add($c)
    }
}

function Set-StepChecks($Panel, [string[]]$Keys) {
    foreach ($c in $Panel.Children) { $c.IsChecked = ($Keys -contains $c.Tag) }
}

function Get-StepChecks($Panel) {
    return @($Panel.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
}

$script:QuickSteps = @('Temporales', 'Caches', 'Dns')
$script:RecSteps = @(Get-StepList | Where-Object { $_.Rec } | ForEach-Object { $_.Key })
$script:StepTitles = @{}
foreach ($s in (Get-StepList)) { $script:StepTitles[$s.Key] = $s.Title }

# ----------------------------------------------------------------------------
#  Inicio
# ----------------------------------------------------------------------------

function Update-Home {
    $ui.HomeCards.Children.Clear()
    $ui.HomeAlerts.Children.Clear()
    $st = Get-QuickStatus
    $alerts = 0

    $sys = $st.Volumes | Where-Object { $_.Id -eq $env:SystemDrive } | Select-Object -First 1
    if ($sys) {
        $c = $(if ($sys.FreePct -lt 10) { $script:Brush.Bad } elseif ($sys.FreePct -lt 20) { $script:Brush.Warn } else { $script:Brush.Ok })
        [void]$ui.HomeCards.Children.Add((New-Card "Espacio libre ($($sys.Id))" (Format-Size $sys.FreeBytes) ('{0:N0}% de {1}' -f $sys.FreePct, (Format-Size $sys.SizeBytes)) $c))
    }
    foreach ($v in @($st.Volumes | Where-Object { $_.Id -ne $env:SystemDrive })) {
        if ($v.FreePct -lt 15) { Add-Alert ('Unidad {0} con poco espacio: {1:N0}% libre.' -f $v.Id, $v.FreePct) $script:Brush.Warn; $alerts++ }
    }
    if ($st.RamTotalGB -gt 0) {
        $used = 100 * (1 - $st.RamFreeGB / $st.RamTotalGB)
        $c = $(if ($used -gt 90) { $script:Brush.Bad } elseif ($used -gt 75) { $script:Brush.Warn } else { $script:Brush.Ok })
        [void]$ui.HomeCards.Children.Add((New-Card 'Memoria en uso' ('{0:N0}%' -f $used) ('{0:N1} GB libres de {1:N1} GB' -f $st.RamFreeGB, $st.RamTotalGB) $c))
    }
    $c = $(if ($st.UptimeDays -gt 14) { $script:Brush.Warn } else { $script:Brush.Ok })
    [void]$ui.HomeCards.Children.Add((New-Card 'Sin reiniciar' ('{0:N1} días' -f $st.UptimeDays) 'Reiniciar de vez en cuando libera memoria' $c))

    $bad = @($st.Disks | Where-Object { $_.Health -and $_.Health -ne 'Healthy' })
    if ($st.Disks.Count -gt 0) {
        $c = $(if ($bad.Count) { $script:Brush.Bad } else { $script:Brush.Ok })
        $txt = $(if ($bad.Count) { 'Revisar' } else { 'Correcta' })
        [void]$ui.HomeCards.Children.Add((New-Card 'Salud de discos' $txt (($st.Disks | ForEach-Object { "$($_.Name) [$($_.Media)]" }) -join ', ') $c))
    }

    $last = @(Get-RunHistory $script:HistoryRoots | Where-Object { $_.Modo -eq 'Real' } | Select-Object -First 1)
    if ($last.Count) {
        [void]$ui.HomeCards.Children.Add((New-Card 'Último mantenimiento' $last[0].Fecha.Split(' ')[0] $last[0].Fecha $script:Brush.Info))
    } else {
        [void]$ui.HomeCards.Children.Add((New-Card 'Último mantenimiento' 'Nunca' 'Aún no hay ejecuciones reales' $script:Brush.Muted))
    }

    $sched = @()
    try { $sched = @(Get-MaintenanceSchedules | Where-Object { $_.Estado -eq 'Activa' }) } catch { }
    if ($sched.Count) {
        $next = ($sched | Where-Object { $_.Proxima } | Sort-Object { [datetime]::ParseExact($_.Proxima, 'dd/MM/yyyy HH:mm', $null) } | Select-Object -First 1)
        [void]$ui.HomeCards.Children.Add((New-Card 'Tareas programadas' "$($sched.Count) activa(s)" ('Próxima: ' + $(if ($next) { $next.Proxima } else { '-' })) $script:Brush.Info))
    } else {
        [void]$ui.HomeCards.Children.Add((New-Card 'Tareas programadas' 'Ninguna' 'Programa una limpieza semanal' $script:Brush.Muted))
    }

    if ($sys -and $sys.FreePct -lt 15) { Add-Alert ('Poco espacio en {0}: ejecuta una limpieza.' -f $sys.Id) $script:Brush.Warn; $alerts++ }
    foreach ($d in $bad) { Add-Alert ("Disco $($d.Name) con estado '$($d.Health)'. Haz una copia de seguridad cuanto antes.") $script:Brush.Bad; $alerts++ }
    if ($st.PendingReboot) { Add-Alert 'Windows tiene un reinicio pendiente.' $script:Brush.Warn; $alerts++ }
    if ($st.UptimeDays -gt 14) { Add-Alert ('El equipo lleva {0:N0} días sin reiniciarse.' -f $st.UptimeDays) $script:Brush.Warn; $alerts++ }
    if (-not $last.Count) { Add-Alert 'Nunca se ha hecho un mantenimiento real con esta herramienta. Empieza con "Simular".' $script:Brush.Info; $alerts++ }
    if (-not $script:IsAdmin) { Add-Alert 'Sin permisos de administrador: abre la aplicación con MaintenanceApp.bat.' $script:Brush.Bad; $alerts++ }
    if ($alerts -eq 0) { Add-Alert 'Todo en orden.' $script:Brush.Ok }
    $ui.TxtHomeSub.Text = "$($st.Os)  -  actualizado a las $(Get-Date -Format 'HH:mm')"
}

# ----------------------------------------------------------------------------
#  Mantenimiento: ejecuta Maintenance.ps1 en otro proceso y lee su salida
# ----------------------------------------------------------------------------

function Set-RunningState([bool]$Running) {
    $ui.BtnRun.IsEnabled = -not $Running
    $ui.BtnCancel.IsEnabled = $Running
    $ui.BtnHomeQuick.IsEnabled = -not $Running
    $ui.BtnHomeFull.IsEnabled = -not $Running
    $ui.BtnHomeSim.IsEnabled = -not $Running
    $ui.MaintSteps.IsEnabled = -not $Running
    $ui.ChkSimulate.IsEnabled = -not $Running
}

function Update-RunGrid {
    $ui.GridRun.ItemsSource = $null
    $ui.GridRun.ItemsSource = @($script:RunRows)
}

function Add-LogLine([string]$Line) {
    $ui.TxtLog.AppendText($Line + "`r`n")
    if ($ui.TxtLog.Text.Length -gt 300000) { $ui.TxtLog.Text = $ui.TxtLog.Text.Substring(100000) }
    $ui.TxtLog.ScrollToEnd()
}

function Start-Maintenance([string[]]$Keys, [bool]$Simulate) {
    if ($script:Proc -and -not $script:Proc.HasExited) { Show-Info 'Ya hay un mantenimiento en curso.'; return }
    if ($Keys.Count -eq 0) { Show-Info 'Elige al menos un paso.'; return }
    $days = 7
    if (-not [int]::TryParse($ui.TxtTempDays.Text, [ref]$days) -or $days -lt 1 -or $days -gt 365) { Show-Info 'Los días de temporales deben ser un número entre 1 y 365.'; return }
    if (-not $Simulate) {
        $running = @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi') | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }
        $msg = "Se va a ejecutar el mantenimiento con estos pasos:`n`n - " + (($Keys | ForEach-Object { $script:StepTitles[$_] }) -join "`n - ")
        if ($Keys -contains 'Reparar') { $msg += "`n`nLa reparación de Windows tarda 30-60 minutos. No apagues el equipo mientras tanto." }
        if ($running -and $Keys -contains 'Caches') { $msg += "`n`nHay navegadores abiertos; su caché se omitirá. Ciérralos antes si quieres limpiarla." }
        $msg += "`n`n¿Continuar?"
        if (-not (Confirm-Action $msg)) { return }
    }

    Show-Page 'PageMaint'
    Set-StepChecks $ui.MaintSteps $Keys
    $ui.ChkSimulate.IsChecked = $Simulate
    $ui.TxtTempDays.Text = "$days"
    $ui.TxtLog.Clear()
    $ui.TxtSummary.Text = ''
    $ui.TxtSummary.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'Fg')
    $ui.BtnOpenLog.IsEnabled = $false
    $ui.Progress.Value = 0
    $ui.TxtProgressDetail.Text = ''
    $ui.TxtCurrent.Text = $(if ($Simulate) { 'Simulando...' } else { 'Iniciando...' })
    $script:RunRows = @()
    $script:RunTotal = $Keys.Count
    $script:RunDone = 0
    $script:RunEnd = $null
    $script:RunWarnings = @()
    $script:EofCount = 0
    $script:LastLogDir = $null
    $script:Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    Update-RunGrid

    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Unattended -GuiMode -NoPause -TempDays {1} -Steps {2}' -f $script:Engine, $days, ($Keys -join ',')
    if ($Simulate) { $argLine += ' -DryRun' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.WorkingDirectory = $script:AppDir
    $script:Proc = [System.Diagnostics.Process]::Start($psi)

    # Dos lectores en segundo plano (stdout y stderr) que vuelcan en una cola;
    # un temporizador de la interfaz la vacía.
    $script:Pool = [runspacefactory]::CreateRunspacePool(1, 2)
    $script:Pool.Open()
    $readerScript = {
        param($Stream, $Queue, $Prefix)
        while ($null -ne ($l = $Stream.ReadLine())) { $Queue.Enqueue($Prefix + $l) }
        $Queue.Enqueue('##EOF')
    }
    $script:Readers = @()
    foreach ($pair in @(@($script:Proc.StandardOutput, ''), @($script:Proc.StandardError, '[stderr] '))) {
        $p = [powershell]::Create()
        $p.RunspacePool = $script:Pool
        [void]$p.AddScript($readerScript).AddArgument($pair[0]).AddArgument($script:Queue).AddArgument($pair[1])
        $script:Readers += New-Object psobject -Property @{ Shell = $p; Handle = $p.BeginInvoke() }
    }
    Set-RunningState $true
    if (-not $SelfTest) { Save-Settings; $script:Timer.Start() }
}

function Receive-RunOutput {
    $line = $null
    $count = 0
    while ($count -lt 500 -and $script:Queue.TryDequeue([ref]$line)) {
        $count++
        if ($line -eq '##EOF') { $script:EofCount++; continue }
        if ($line.StartsWith('##')) { Read-Marker $line.Substring(2); continue }
        # Barras de progreso de DISM / SFC: se muestran aparte para no llenar el registro.
        if ($line -match '^\s*\[[= ]*\d+(\.\d+)?%[= ]*\]\s*$' -or $line -match '^\s*(Verification|Verificaci)\S*\s.*\d+%') {
            $ui.TxtProgressDetail.Text = $line.Trim()
            continue
        }
        if ($line.Trim().Length -eq 0 -and $ui.TxtLog.Text.EndsWith("`r`n`r`n")) { continue }
        Add-LogLine $line
    }
    if ($script:EofCount -ge 2 -and $script:Proc -and $script:Proc.HasExited) { Complete-Run }
}

function Read-Marker([string]$Marker) {
    $p = $Marker.Split('|')
    switch ($p[0]) {
        'PLAN' {
            $keys = @($p[1].Split(',') | Where-Object { $_ })
            $script:RunTotal = [Math]::Max(1, $keys.Count)
            $script:RunRows = @($keys | ForEach-Object {
                    New-Object psobject -Property @{ Key = $_; Paso = $script:StepTitles[$_]; Estado = 'Pendiente'; Tiempo = ''; Detalle = '' }
                })
            Update-RunGrid
        }
        'STEP' {
            foreach ($r in $script:RunRows) { if ($r.Key -eq $p[1]) { $r.Estado = 'En curso' } }
            $ui.TxtCurrent.Text = 'En curso: ' + $script:StepTitles[$p[1]]
            $ui.TxtProgressDetail.Text = ''
            Update-RunGrid
        }
        'DONE' {
            foreach ($r in $script:RunRows) {
                if ($r.Key -eq $p[1]) { $r.Estado = $p[2]; $r.Tiempo = "$($p[3]) s"; $r.Detalle = $(if ($p.Count -gt 4) { $p[4] } else { '' }) }
            }
            $script:RunDone++
            $ui.Progress.Value = $script:RunDone / $script:RunTotal
            Update-RunGrid
        }
        'WARN' { $script:RunWarnings += ($p[1..($p.Count - 1)] -join '|') }
        'END' {
            $script:RunEnd = New-Object psobject -Property @{ Code = [int]$p[1]; Before = [double]$p[2]; After = [double]$p[3]; Dir = ($p[4..($p.Count - 1)] -join '|') }
            $script:LastLogDir = $script:RunEnd.Dir
        }
    }
}

function Complete-Run {
    $script:Timer.Stop()
    foreach ($r in $script:Readers) { try { $r.Shell.EndInvoke($r.Handle) | Out-Null; $r.Shell.Dispose() } catch { } }
    $script:Readers = @()
    try { $script:Pool.Close(); $script:Pool.Dispose() } catch { }
    $exit = $script:Proc.ExitCode
    $script:Proc = $null
    Set-RunningState $false
    $ui.Progress.Value = 1
    $ui.TxtProgressDetail.Text = ''

    if ($script:RunEnd) {
        $freed = [Math]::Max(0, $script:RunEnd.After - $script:RunEnd.Before)
        $errors = @($script:RunRows | Where-Object { $_.Estado -eq 'Error' }).Count
        $sim = [bool]$ui.ChkSimulate.IsChecked
        $txt = $(if ($sim) { 'Simulación terminada.' } elseif ($errors) { "Terminado con $errors error(es)." } else { 'Mantenimiento terminado.' })
        if (-not $sim) { $txt += '  Espacio liberado en ' + $env:SystemDrive + ': ' + (Format-Size $freed) + '.' }
        if ($script:RunWarnings.Count) { $txt += '  Avisos: ' + ($script:RunWarnings -join ' / ') }
        if (-not $sim -and ($script:RunRows | Where-Object { $_.Key -eq 'Reparar' })) { $txt += '  Se recomienda reiniciar el equipo.' }
        $ui.TxtSummary.Text = $txt
        $ui.TxtSummary.Foreground = New-Brush $(if ($errors) { $script:Brush.Bad } elseif ($script:RunWarnings.Count) { $script:Brush.Warn } else { $script:Brush.Ok })
        $ui.TxtCurrent.Text = $(if ($errors) { 'Terminado con errores' } else { 'Terminado' })
        $ui.BtnOpenLog.IsEnabled = [bool]$script:LastLogDir
    } else {
        $ui.TxtCurrent.Text = 'Detenido'
        $ui.TxtSummary.Text = "El proceso terminó sin completar (código $exit). Revisa el registro de arriba."
        $ui.TxtSummary.Foreground = New-Brush $script:Brush.Bad
    }
    if (-not $SelfTest) { Invoke-Safe { Update-Home } }
}

function Stop-Maintenance {
    if (-not $script:Proc -or $script:Proc.HasExited) { return }
    $msg = '¿Cancelar el mantenimiento?'
    if (@($script:RunRows | Where-Object { $_.Key -eq 'Reparar' -and $_.Estado -eq 'En curso' }).Count) {
        $msg = "La reparación de Windows está en curso. Interrumpirla puede dejarla incompleta.`n`n¿Cancelar de todos modos?"
    }
    if (-not (Confirm-Action $msg)) { return }
    & taskkill.exe /PID $script:Proc.Id /T /F | Out-Null
    Add-LogLine '*** Cancelado por el usuario ***'
}

# ----------------------------------------------------------------------------
#  Arranque de Windows
# ----------------------------------------------------------------------------

function Update-Startup {
    $apps = @(Get-StartupApps)
    $ui.GridStartup.ItemsSource = $apps
    $on = @($apps | Where-Object { $_.Activo }).Count
    $ui.TxtStartupInfo.Text = "$on activados de $($apps.Count)"
}

function Set-SelectedStartup([bool]$Enabled) {
    $sel = $ui.GridStartup.SelectedItem
    if (-not $sel) { Show-Info 'Selecciona un programa de la lista.'; return }
    if ($sel.ApprovedKey -like 'HKLM:*' -and -not $script:IsAdmin) { Show-Info 'Este programa es de todo el equipo y requiere permisos de administrador.'; return }
    Set-StartupAppEnabled -ApprovedKey $sel.ApprovedKey -ValueName $sel.ValueName -Enabled $Enabled
    Update-Startup
}

# ----------------------------------------------------------------------------
#  Tareas programadas
# ----------------------------------------------------------------------------

function Update-Schedules {
    $ui.GridSchedules.ItemsSource = @(Get-MaintenanceSchedules)
}

function Get-SelectedSchedule {
    $sel = $ui.GridSchedules.SelectedItem
    if (-not $sel) { Show-Info 'Selecciona una tarea de la lista.' }
    return $sel
}

function New-ScheduleFromForm {
    if (-not $script:IsAdmin) { Show-Info 'Crear tareas requiere permisos de administrador.'; return }
    $keys = Get-StepChecks $ui.SchSteps
    New-MaintenanceSchedule -Name $ui.TxtSchName.Text.Trim() -Frequency $ui.CmbSchFreq.SelectedValue -Day $ui.CmbSchDay.SelectedValue -Time $ui.TxtSchTime.Text.Trim() -StepKeys $keys
    Update-Schedules
    Show-Info ("Tarea '{0}' creada." -f $ui.TxtSchName.Text.Trim())
}

# ----------------------------------------------------------------------------
#  Historial
# ----------------------------------------------------------------------------

function Update-History {
    $h = @(Get-RunHistory $script:HistoryRoots)
    $ui.GridHistory.ItemsSource = $h
    $ui.TxtHistorySub.Text = "$($h.Count) ejecución(es) guardadas en $script:LogRoot"
    $ui.TxtHistoryLog.Text = ''
    if ($h.Count) { $ui.GridHistory.SelectedIndex = 0 }
}

# ----------------------------------------------------------------------------
#  Herramientas
# ----------------------------------------------------------------------------

function Update-PowerPlan {
    try {
        $out = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
        if ($out -match '\(([^)]+)\)\s*$') { $ui.TxtPowerPlan.Text = 'Plan activo: ' + $Matches[1] } else { $ui.TxtPowerPlan.Text = $out }
    } catch { $ui.TxtPowerPlan.Text = 'No disponible.' }
}

function Set-PowerPlan([string]$Scheme) {
    $out = & powercfg.exe /setactive $Scheme 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Show-Error ("No se pudo cambiar el plan. Puede que este equipo no lo tenga disponible.`n`n" + $out.Trim()) }
    Update-PowerPlan
}

function Open-Target([string]$Target, [string]$Arguments) {
    try {
        if ($Arguments) { Start-Process -FilePath $Target -ArgumentList $Arguments } else { Start-Process -FilePath $Target }
    } catch { Show-Error ("No se pudo abrir {0}: {1}" -f $Target, $_.Exception.Message) }
}

$script:Tools = @(
    @('Administrador de tareas', 'taskmgr.exe', ''),
    @('Monitor de recursos', 'resmon.exe', ''),
    @('Liberador de espacio', 'cleanmgr.exe', ''),
    @('Optimizar unidades', 'dfrgui.exe', ''),
    @('Sensor de almacenamiento', 'ms-settings:storagesense', ''),
    @('Windows Update', 'ms-settings:windowsupdate', ''),
    @('Aplicaciones instaladas', 'ms-settings:appsfeatures', ''),
    @('Aplicaciones de inicio', 'ms-settings:startupapps', ''),
    @('Restaurar sistema', 'rstrui.exe', ''),
    @('Información del sistema', 'msinfo32.exe', ''),
    @('Visor de eventos', 'eventvwr.msc', ''),
    @('Servicios', 'services.msc', ''),
    @('Programador de tareas', 'taskschd.msc', ''),
    @('Seguridad de Windows', 'windowsdefender:', '')
)

# ----------------------------------------------------------------------------
#  Tema y preferencias
# ----------------------------------------------------------------------------

$script:Themes = @{
    Claro  = @{ AppBg = '#F3F4F6'; CardBg = '#FFFFFF'; InputBg = '#FFFFFF'; Fg = '#111827'; Muted = '#6B7280'; Line = '#E5E7EB'; Line2 = '#D1D5DB'; Hover = '#DBEAFE' }
    Oscuro = @{ AppBg = '#0B1120'; CardBg = '#1E293B'; InputBg = '#0F172A'; Fg = '#E5E7EB'; Muted = '#94A3B8'; Line = '#334155'; Line2 = '#475569'; Hover = '#1E3A8A' }
}

function Set-Theme([string]$Mode) {
    $dark = $(if ($Mode -eq 'Auto') { Test-SystemDarkMode } else { $Mode -eq 'Oscuro' })
    $palette = $(if ($dark) { $script:Themes.Oscuro } else { $script:Themes.Claro })
    foreach ($k in $palette.Keys) { $window.Resources[$k] = New-Brush $palette[$k] }
    $label = @{ Auto = 'automático'; Claro = 'claro'; Oscuro = 'oscuro' }
    $ui.BtnTheme.Content = 'Tema: ' + $label[$Mode]
    $script:IsDark = $dark
}

function Save-Settings {
    if ($script:SkipSave) { return }
    try {
        $d = 0
        if ([int]::TryParse($ui.TxtTempDays.Text, [ref]$d) -and $d -ge 1 -and $d -le 365) { $script:Settings.TempDays = $d }
        $script:Settings.MaintSteps = @(Get-StepChecks $ui.MaintSteps)
        if ($ui.TxtSpacePath.Text) { $script:Settings.SpacePath = $ui.TxtSpacePath.Text }
        Save-AppSettings $script:Settings
    } catch { }
}

# ----------------------------------------------------------------------------
#  Espacio en disco (análisis en segundo plano)
# ----------------------------------------------------------------------------

$script:Space = $null

function Start-SpaceScan {
    if ($script:Space) { return }
    $path = $ui.TxtSpacePath.Text.Trim()
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container)) { Show-Info 'Elige una carpeta que exista.'; return }
    $progress = [hashtable]::Synchronized(@{ Count = 0 })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
            param($Engine, $Path, $Progress)
            . $Engine
            Get-SpaceReport -Path $Path -TopFiles 100 -Progress $Progress
        }).AddArgument($script:Engine).AddArgument($path).AddArgument($progress)
    $script:Space = New-Object psobject -Property @{ Shell = $ps; Runspace = $rs; Handle = $ps.BeginInvoke(); Progress = $progress; Started = Get-Date }
    $ui.BtnSpaceRun.IsEnabled = $false
    $ui.BtnSpaceCancel.IsEnabled = $true
    $ui.GridSpaceFolders.ItemsSource = $null
    $ui.GridSpaceFiles.ItemsSource = $null
    $ui.TxtSpaceStatus.Text = 'Analizando...'
    $script:Settings.SpacePath = $path
    if (-not $SelfTest) { $script:SpaceTimer.Start() }
}

function Receive-SpaceScan {
    $sc = $script:Space
    if (-not $sc) { return }
    if (-not $sc.Handle.IsCompleted) {
        $ui.TxtSpaceStatus.Text = ('Analizando... {0:N0} archivos ({1:N0} s)' -f $sc.Progress.Count, ((Get-Date) - $sc.Started).TotalSeconds)
        return
    }
    $script:SpaceTimer.Stop()
    $script:Space = $null
    $ui.BtnSpaceRun.IsEnabled = $true
    $ui.BtnSpaceCancel.IsEnabled = $false
    try {
        $res = @($sc.Shell.EndInvoke($sc.Handle))
        if ($sc.Shell.Streams.Error.Count -gt 0 -and $res.Count -eq 0) { throw $sc.Shell.Streams.Error[0].Exception }
        $r = $res[-1]
        $ui.GridSpaceFolders.ItemsSource = @($r.Carpetas)
        $ui.GridSpaceFiles.ItemsSource = @($r.ArchivosGrandes)
        $txt = ('{0} en {1:N0} archivos, {2:N0} s' -f (Format-Size $r.TotalBytes), $r.Archivos, ((Get-Date) - $sc.Started).TotalSeconds)
        if ($r.Errores) { $txt += (' ({0} carpetas sin permiso de lectura)' -f $r.Errores) }
        $ui.TxtSpaceStatus.Text = $txt
        $script:LastSpace = $r
    } catch {
        if ($sc.Shell.InvocationStateInfo.State -eq 'Stopped') { $ui.TxtSpaceStatus.Text = 'Cancelado.' }
        else { $ui.TxtSpaceStatus.Text = 'Error: ' + $_.Exception.Message }
    } finally {
        try { $sc.Shell.Dispose(); $sc.Runspace.Close(); $sc.Runspace.Dispose() } catch { }
    }
}

function Stop-SpaceScan {
    if ($script:Space) { try { $script:Space.Shell.BeginStop($null, $null) | Out-Null } catch { } }
}

function Open-InExplorer([string]$Path, [bool]$Select) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    if ($Select) { Open-Target 'explorer.exe' ('/select,"' + $Path + '"') } else { Open-Target 'explorer.exe' ('"' + $Path + '"') }
}

# ----------------------------------------------------------------------------
#  Rendimiento
# ----------------------------------------------------------------------------

$script:PerfSample = $null

function Update-Perf {
    $u = Get-ProcessUsage -Previous $script:PerfSample
    $script:PerfSample = $u.Sample
    $rows = @($u.Rows | Where-Object { $_.Id -ne 0 -and $_.Nombre -ne 'Idle' })
    if ($ui.RbPerfMem.IsChecked) { $rows = @($rows | Sort-Object MemoriaBytes -Descending) }
    else { $rows = @($rows | Sort-Object @{ Expression = 'Cpu'; Descending = $true }, @{ Expression = 'MemoriaBytes'; Descending = $true }) }
    $ui.GridPerf.ItemsSource = @($rows | Select-Object -First 25)
    $ui.PerfCards.Children.Clear()
    $st = Get-QuickStatus
    $c = $(if ($u.CpuTotal -gt 85) { $script:Brush.Bad } elseif ($u.CpuTotal -gt 60) { $script:Brush.Warn } else { $script:Brush.Ok })
    [void]$ui.PerfCards.Children.Add((New-Card 'Procesador' ("$($u.CpuTotal)%") ("$([Environment]::ProcessorCount) núcleos lógicos") $c))
    if ($st.RamTotalGB -gt 0) {
        $used = 100 * (1 - $st.RamFreeGB / $st.RamTotalGB)
        $c = $(if ($used -gt 90) { $script:Brush.Bad } elseif ($used -gt 75) { $script:Brush.Warn } else { $script:Brush.Ok })
        [void]$ui.PerfCards.Children.Add((New-Card 'Memoria' ('{0:N0}%' -f $used) ('{0:N1} GB libres de {1:N1} GB' -f $st.RamFreeGB, $st.RamTotalGB) $c))
    }
    [void]$ui.PerfCards.Children.Add((New-Card 'Procesos' "$($rows.Count)" 'En ejecución ahora' $script:Brush.Info))
}

# ----------------------------------------------------------------------------
#  Actualizaciones y desinstalación
# ----------------------------------------------------------------------------

$script:Update = $null
$script:UpdateUrl = $null

function Start-UpdateCheck([bool]$Manual) {
    if ($script:Update) { return }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({ param($Engine) . $Engine; Get-LatestRelease }).AddArgument($script:Engine)
    $script:Update = New-Object psobject -Property @{ Shell = $ps; Runspace = $rs; Handle = $ps.BeginInvoke(); Manual = $Manual }
    if ($Manual) { $ui.BtnCheckUpdate.IsEnabled = $false; $ui.BtnCheckUpdate.Content = 'Buscando...' }
    $script:UpdateTimer.Start()
}

function Receive-UpdateCheck {
    $u = $script:Update
    if (-not $u -or -not $u.Handle.IsCompleted) { return }
    $script:UpdateTimer.Stop()
    $script:Update = $null
    $ui.BtnCheckUpdate.IsEnabled = $true
    $ui.BtnCheckUpdate.Content = 'Buscar actualizaciones'
    $rel = $null
    try { $rel = @($u.Shell.EndInvoke($u.Handle)) | Select-Object -Last 1 } catch { }
    try { $u.Shell.Dispose(); $u.Runspace.Close(); $u.Runspace.Dispose() } catch { }
    if ($rel -and (Compare-AppVersion $rel.Version $script:AppVersion) -gt 0) {
        $script:UpdateUrl = $rel.Url
        $ui.TxtBannerUpdate.Text = ("Hay una versión nueva: {0} (tienes la {1}). Descárgala, descomprímela encima de esta carpeta y vuelve a abrir la aplicación." -f $rel.Version, $script:AppVersion)
        $ui.BannerUpdate.Visibility = 'Visible'
        if ($u.Manual) { Show-Page 'PageHome' }
    } elseif ($u.Manual) {
        if ($rel) { Show-Info ("Tienes la última versión ({0})." -f $script:AppVersion) }
        else { Show-Info 'No se pudo consultar GitHub. Revisa la conexión a Internet o inténtalo más tarde.' }
    }
}

function Invoke-Uninstall {
    $a = Get-InstalledArtifacts
    $lines = @()
    if ($a.Tasks.Count) { $lines += ('- {0} tarea(s) programada(s)' -f $a.Tasks.Count) }
    if ($a.Shortcuts.Count) { $lines += ('- {0} acceso(s) directo(s)' -f $a.Shortcuts.Count) }
    if ($a.SettingsDir) { $lines += '- Preferencias guardadas' }
    $msg = "Se quitará lo que la aplicación dejó en el equipo:`n`n" + $(if ($lines.Count) { $lines -join "`n" } else { '- (no hay tareas, accesos directos ni preferencias)' })
    $msg += "`n`nNo se deshacen los programas de arranque que desactivaste (puedes reactivarlos antes desde Arranque de Windows).`n`n¿Continuar?"
    if (-not (Confirm-Action $msg)) { return }
    $logs = $false
    if ($a.LogRoots.Count) { $logs = Confirm-Action ("¿Borrar también los registros de mantenimiento?`n`n" + ($a.LogRoots -join "`n")) }
    $done = @(Uninstall-MaintenanceTool -RemoveLogs:$logs)
    $script:SkipSave = $true
    Show-Info ("Desinstalación terminada.`n`n" + $(if ($done.Count) { ($done | ForEach-Object { '- ' + $_ }) -join "`n" } else { 'No había nada que quitar.' }) + "`n`nPara terminar, cierra la aplicación y borra esta carpeta:`n" + $script:AppDir)
    $window.Close()
}

# ----------------------------------------------------------------------------
#  Enlaces de eventos
# ----------------------------------------------------------------------------

foreach ($b in $ui.NavPanel.Children) {
    $b.Add_Click({ param($sender, $e) Show-Page $sender.Tag })
}

$ui.BtnHomeQuick.Add_Click({ Invoke-Safe { Start-Maintenance $script:QuickSteps $false } })
$ui.BtnHomeFull.Add_Click({ Invoke-Safe { Start-Maintenance $script:RecSteps $false } })
$ui.BtnHomeSim.Add_Click({ Invoke-Safe { Start-Maintenance $script:RecSteps $true } })
$ui.BtnHomeRefresh.Add_Click({ Invoke-Safe { Update-Home } })

$ui.BtnSelQuick.Add_Click({ Set-StepChecks $ui.MaintSteps $script:QuickSteps })
$ui.BtnSelRec.Add_Click({ Set-StepChecks $ui.MaintSteps $script:RecSteps })
$ui.BtnSelNone.Add_Click({ Set-StepChecks $ui.MaintSteps @() })
$ui.BtnRun.Add_Click({ Invoke-Safe { Start-Maintenance (Get-StepChecks $ui.MaintSteps) ([bool]$ui.ChkSimulate.IsChecked) } })
$ui.BtnCancel.Add_Click({ Invoke-Safe { Stop-Maintenance } })
$ui.BtnOpenLog.Add_Click({ if ($script:LastLogDir) { Open-Target 'explorer.exe' ('"' + $script:LastLogDir + '"') } })

$ui.BtnStartupDisable.Add_Click({ Invoke-Safe { Set-SelectedStartup $false } })
$ui.BtnStartupEnable.Add_Click({ Invoke-Safe { Set-SelectedStartup $true } })
$ui.BtnStartupRefresh.Add_Click({ Invoke-Safe { Update-Startup } })

$ui.BtnSchCreate.Add_Click({ Invoke-Safe { New-ScheduleFromForm } })
$ui.BtnSchPreset.Add_Click({
        $ui.TxtSchName.Text = 'Limpieza semanal'
        $ui.CmbSchFreq.SelectedValue = 'Semanal'
        $ui.CmbSchDay.SelectedValue = 'Saturday'
        $ui.TxtSchTime.Text = '13:00'
        Set-StepChecks $ui.SchSteps @('Diagnostico', 'Temporales', 'Caches', 'Dns', 'Optimizar')
    })
$ui.BtnSchRefresh.Add_Click({ Invoke-Safe { Update-Schedules } })
$ui.BtnSchRunNow.Add_Click({ Invoke-Safe {
            $s = Get-SelectedSchedule
            if ($s) { Start-MaintenanceSchedule $s.Nombre; Show-Info "Tarea '$($s.Nombre)' iniciada en segundo plano. El resultado aparecerá en Historial."; Update-Schedules }
        } })
$ui.BtnSchToggle.Add_Click({ Invoke-Safe {
            $s = Get-SelectedSchedule
            if ($s) { Set-MaintenanceScheduleEnabled $s.Nombre ($s.Estado -eq 'Pausada'); Update-Schedules }
        } })
$ui.BtnSchDelete.Add_Click({ Invoke-Safe {
            $s = Get-SelectedSchedule
            if ($s -and (Confirm-Action "¿Eliminar la tarea '$($s.Nombre)'?")) { Remove-MaintenanceSchedule $s.Nombre; Update-Schedules }
        } })
$ui.CmbSchFreq.Add_SelectionChanged({ $ui.CmbSchDay.IsEnabled = ($ui.CmbSchFreq.SelectedValue -ne 'Diaria') })

$ui.BtnHistOpen.Add_Click({
        $sel = $ui.GridHistory.SelectedItem
        $target = $(if ($sel) { $sel.Path } else { $script:LogRoot })
        if (Test-Path -LiteralPath $target) { Open-Target 'explorer.exe' ('"' + $target + '"') } else { Show-Info 'Todavía no hay registros.' }
    })
$ui.BtnHistRefresh.Add_Click({ Invoke-Safe { Update-History } })
$ui.GridHistory.Add_SelectionChanged({
        $sel = $ui.GridHistory.SelectedItem
        if ($sel) { try { $ui.TxtHistoryLog.Text = [IO.File]::ReadAllText($sel.Log) } catch { $ui.TxtHistoryLog.Text = $_.Exception.Message } }
    })

$ui.BtnPowerBalanced.Add_Click({ Invoke-Safe { Set-PowerPlan 'SCHEME_BALANCED' } })
$ui.BtnPowerHigh.Add_Click({ Invoke-Safe { Set-PowerPlan 'SCHEME_MIN' } })
$ui.BtnPowerSettings.Add_Click({ Open-Target 'control.exe' 'powercfg.cpl' })

foreach ($t in $script:Tools) {
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $t[0]
    $btn.Style = $window.FindResource('Btn')
    $btn.Width = 190
    $btn.Tag = $t
    $btn.Add_Click({ param($sender, $e) Open-Target $sender.Tag[1] $sender.Tag[2] })
    [void]$ui.ToolsPanel.Children.Add($btn)
}
$ui.BtnLogFolder.Add_Click({
        if (-not (Test-Path -LiteralPath $script:LogRoot)) { New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null }
        Open-Target 'explorer.exe' ('"' + $script:LogRoot + '"')
    })
$ui.BtnShortcut.Add_Click({ Invoke-Safe {
            $made = @(New-AppShortcut)
            if ($made.Count) { Show-Info ("Acceso directo creado en:`n`n" + ($made -join "`n") + "`n`nSi mueves la carpeta de la aplicación, vuelve a crearlo.") }
            else { Show-Info 'No se pudo crear el acceso directo.' }
        } })

$ui.BtnTheme.Add_Click({
        $next = @{ Auto = 'Claro'; Claro = 'Oscuro'; Oscuro = 'Auto' }
        $script:Settings.Theme = $next[$script:Settings.Theme]
        Set-Theme $script:Settings.Theme
        Save-Settings
    })
$ui.BtnSpaceRun.Add_Click({ Invoke-Safe { Start-SpaceScan } })
$ui.BtnSpaceCancel.Add_Click({ Stop-SpaceScan })
$ui.BtnSpaceUser.Add_Click({ $ui.TxtSpacePath.Text = $env:USERPROFILE; Invoke-Safe { Start-SpaceScan } })
$ui.BtnSpaceDownloads.Add_Click({ $ui.TxtSpacePath.Text = (Join-Path $env:USERPROFILE 'Downloads'); Invoke-Safe { Start-SpaceScan } })
$ui.BtnSpaceDrive.Add_Click({
        if (Confirm-Action 'Analizar toda la unidad puede tardar varios minutos. ¿Continuar?') { $ui.TxtSpacePath.Text = $env:SystemDrive + '\'; Invoke-Safe { Start-SpaceScan } }
    })
$ui.BtnSpaceBrowse.Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Elige la carpeta que quieres analizar'
        if ($ui.TxtSpacePath.Text -and (Test-Path -LiteralPath $ui.TxtSpacePath.Text)) { $dlg.SelectedPath = $ui.TxtSpacePath.Text }
        if ($dlg.ShowDialog() -eq 'OK') { $ui.TxtSpacePath.Text = $dlg.SelectedPath }
    })
$ui.GridSpaceFolders.Add_MouseDoubleClick({ $s = $ui.GridSpaceFolders.SelectedItem; if ($s) { Open-InExplorer $s.Ruta $false } })
$ui.GridSpaceFiles.Add_MouseDoubleClick({ $s = $ui.GridSpaceFiles.SelectedItem; if ($s) { Open-InExplorer $s.Ruta $true } })
$ui.RbPerfCpu.Add_Checked({ if ($ui.PagePerf.Visibility -eq 'Visible') { Invoke-Safe { Update-Perf } } })
$ui.RbPerfMem.Add_Checked({ if ($ui.PagePerf.Visibility -eq 'Visible') { Invoke-Safe { Update-Perf } } })
$ui.BtnPerfTaskmgr.Add_Click({ Open-Target 'taskmgr.exe' '' })

$script:SpaceTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:SpaceTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:SpaceTimer.Add_Tick({ try { Receive-SpaceScan } catch { } })
$script:PerfTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:PerfTimer.Interval = [TimeSpan]::FromSeconds(2)
$script:PerfTimer.Add_Tick({ try { Update-Perf } catch { } })
$ui.BtnCheckUpdate.Add_Click({ Start-UpdateCheck $true })
$ui.BtnUpdateOpen.Add_Click({ if ($script:UpdateUrl) { Open-Target $script:UpdateUrl '' } })
$ui.BtnUninstall.Add_Click({ Invoke-Safe { Invoke-Uninstall } })
$ui.ChkAutoUpdate.Add_Click({ $script:Settings.CheckUpdates = [bool]$ui.ChkAutoUpdate.IsChecked; Save-Settings })
$script:UpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:UpdateTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:UpdateTimer.Add_Tick({ try { Receive-UpdateCheck } catch { } })
$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:Timer.Add_Tick({ try { Receive-RunOutput } catch { Add-LogLine ('Error de interfaz: ' + $_.Exception.Message) } })

$window.Add_Closing({
        param($sender, $e)
        if ($script:Proc -and -not $script:Proc.HasExited) {
            if (Confirm-Action 'Hay un mantenimiento en curso. Si cierras, se cancelará. ¿Cerrar de todos modos?') {
                & taskkill.exe /PID $script:Proc.Id /T /F | Out-Null
            } else { $e.Cancel = $true; return }
        }
        Stop-SpaceScan
        Save-Settings
    })

# ----------------------------------------------------------------------------
#  Estado inicial
# ----------------------------------------------------------------------------

$script:Settings = Get-AppSettings
Set-Theme $script:Settings.Theme
New-StepChecks $ui.MaintSteps $script:Settings.MaintSteps
$ui.TxtTempDays.Text = "$($script:Settings.TempDays)"
$ui.TxtSpacePath.Text = $script:Settings.SpacePath
$ui.ChkAutoUpdate.IsChecked = [bool]$script:Settings.CheckUpdates
New-StepChecks $ui.SchSteps @('Diagnostico', 'Temporales', 'Caches', 'Dns', 'Optimizar')
$daysEs = [ordered]@{ Monday = 'Lunes'; Tuesday = 'Martes'; Wednesday = 'Miércoles'; Thursday = 'Jueves'; Friday = 'Viernes'; Saturday = 'Sábado'; Sunday = 'Domingo' }
$ui.CmbSchDay.ItemsSource = @($daysEs.Keys | ForEach-Object { New-Object psobject -Property @{ K = $_; L = $daysEs[$_] } })
$ui.CmbSchDay.DisplayMemberPath = 'L'
$ui.CmbSchDay.SelectedValuePath = 'K'
$ui.CmbSchDay.SelectedValue = 'Saturday'
$ui.CmbSchFreq.ItemsSource = @(Get-FrequencyList | ForEach-Object { New-Object psobject -Property @{ K = $_.Key; L = $_.Label } })
$ui.CmbSchFreq.DisplayMemberPath = 'L'
$ui.CmbSchFreq.SelectedValuePath = 'K'
$ui.CmbSchFreq.SelectedValue = 'Semanal'

$ui.TxtVersion.Text = 'Tool ' + $script:AppVersion
$ui.TxtAppInfo.Text = ('Versión {0}. Instalada en {1}. Los registros se guardan en {2} y se borran solos a los 90 días.' -f $script:AppVersion, $script:AppDir, $script:LogRoot)
$ui.TxtAdmin.Text = $(if ($script:IsAdmin) { 'Administrador: sí' } else { 'Administrador: NO (funciones limitadas)' })
$ui.TxtUser.Text = 'Usuario: ' + $env:USERNAME
if ($InvokedBy -and ($InvokedBy -ine $env:USERNAME)) {
    $ui.BannerUser.Visibility = 'Visible'
    $ui.TxtBannerUser.Text = "La aplicación la abrió '$InvokedBy' pero se ejecuta como '$($env:USERNAME)'. Temporales, caché y arranque se aplicarán a '$($env:USERNAME)'."
}

# ----------------------------------------------------------------------------
#  Autoprueba (CI): carga todo, ejecuta una simulación real y sale
# ----------------------------------------------------------------------------

if ($SelfTest) {
    $fail = 0
    function Check([bool]$Cond, [string]$Name) {
        if ($Cond) { Write-Host "  ok    $Name" } else { Write-Host "  FALLO $Name"; $script:fail++ }
    }
    $missing = @($ui.Keys | Where-Object { -not $ui[$_] })
    Check ($missing.Count -eq 0) ('todos los controles existen ' + ($missing -join ','))
    try { Update-Home; Check ($ui.HomeCards.Children.Count -ge 3) 'panel de inicio con tarjetas' } catch { Check $false ('inicio: ' + $_) }
    try { Update-Startup; Check ($null -ne $ui.GridStartup.ItemsSource) 'lista de arranque' } catch { Check $false ('arranque: ' + $_) }
    try { Update-Schedules; Check $true 'lista de tareas' } catch { Check $false ('tareas: ' + $_) }
    try { Update-History; Check $true 'historial' } catch { Check $false ('historial: ' + $_) }
    Update-PowerPlan
    Check ($ui.TxtPowerPlan.Text.Length -gt 0) 'plan de energia'
    foreach ($p in $script:Pages) { Show-Page $p }
    Check ($ui.PageTools.Visibility -eq 'Visible') 'navegacion entre secciones'

    try {
        $window.Show()
        $window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Render)
        Check $true 'ventana mostrada'
    } catch { Check $false ('mostrar ventana: ' + $_.Exception.Message) }

    Start-Maintenance @('Diagnostico', 'Temporales', 'Caches', 'Dns') $true
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($script:Proc -and $sw.Elapsed.TotalSeconds -lt 180) {
        Receive-RunOutput
        $window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
        Start-Sleep -Milliseconds 100
    }
    Check ($null -eq $script:Proc) 'la simulacion termino'
    Check ($null -ne $script:RunEnd) 'se recibio el marcador de fin'
    Check ($script:RunRows.Count -eq 4) ('4 pasos en la tabla (' + $script:RunRows.Count + ')')
    Check (@($script:RunRows | Where-Object { $_.Estado -notin @('OK', 'Simulado') }).Count -eq 0) ('todos los pasos OK/Simulado: ' + (($script:RunRows | ForEach-Object { $_.Estado }) -join ','))
    Check ($ui.TxtLog.Text.Length -gt 100) 'el registro en pantalla tiene contenido'
    Check ($ui.TxtSummary.Text -like 'Simulaci*') ('resumen: ' + $ui.TxtSummary.Text)
    if ($script:LastLogDir) { Check (Test-Path -LiteralPath (Join-Path $script:LastLogDir 'resumen.log')) 'resumen.log creado' }
    if ($script:LastLogDir -and (Test-Path -LiteralPath $script:LastLogDir)) { Remove-Item -LiteralPath $script:LastLogDir -Recurse -Force -ErrorAction SilentlyContinue }
    try {
        Update-Perf
        Start-Sleep -Milliseconds 600
        Update-Perf
        Check (@($ui.GridPerf.ItemsSource).Count -gt 0) 'rendimiento lista procesos'
        Check ($ui.PerfCards.Children.Count -ge 2) 'rendimiento con tarjetas'
    } catch { Check $false ('rendimiento: ' + $_.Exception.Message) }

    $spaceDir = Join-Path ([IO.Path]::GetTempPath()) ('mb-space-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $spaceDir 'grande') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $spaceDir 'chica') -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $spaceDir 'grande\video.bin'), (New-Object byte[] 3000000))
    [IO.File]::WriteAllBytes((Join-Path $spaceDir 'chica\nota.txt'), (New-Object byte[] 1000))
    $ui.TxtSpacePath.Text = $spaceDir
    Start-SpaceScan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($script:Space -and $sw.Elapsed.TotalSeconds -lt 60) { Receive-SpaceScan; Start-Sleep -Milliseconds 100 }
    $folders = @($ui.GridSpaceFolders.ItemsSource)
    Check ($folders.Count -eq 2 -and $folders[0].Nombre -eq 'grande') ('espacio: carpetas ordenadas por tamano (' + (($folders | ForEach-Object { $_.Nombre }) -join ',') + ')')
    Check (@($ui.GridSpaceFiles.ItemsSource)[0].Nombre -eq 'video.bin') 'espacio: archivo mas grande primero'
    Check (Test-Path -LiteralPath (Join-Path $spaceDir 'grande\video.bin')) 'espacio: no borra nada'
    Remove-Item -LiteralPath $spaceDir -Recurse -Force -ErrorAction SilentlyContinue

    Start-UpdateCheck $false
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($script:Update -and $sw.Elapsed.TotalSeconds -lt 30) { Receive-UpdateCheck; Start-Sleep -Milliseconds 200 }
    Check ($null -eq $script:Update) 'comprobacion de version termina sin bloquear'
    Check ($ui.BtnCheckUpdate.IsEnabled) 'boton de actualizacion queda habilitado'
    $a = Get-InstalledArtifacts
    Check ($null -ne $a) 'lista lo instalado para desinstalar'

    foreach ($m in 'Oscuro', 'Claro', 'Auto') { Set-Theme $m }
    Set-Theme 'Oscuro'
    Check ($window.Resources['CardBg'].Color.ToString() -eq '#FF1E293B') 'tema oscuro aplicado'
    Update-Home
    Check ($ui.HomeCards.Children.Count -ge 3) 'inicio se redibuja con tema oscuro'
    Set-Theme 'Claro'

    try { $window.Close() } catch { }
    Write-Host ''
    if ($script:fail) { Write-Host "$($script:fail) comprobacion(es) fallaron."; exit 1 }
    Write-Host 'Autoprueba de la interfaz correcta.'
    exit 0
}

$window.Add_ContentRendered({
        Invoke-Safe { Update-Home }
        if ($script:Settings.CheckUpdates) { Start-UpdateCheck $false }
    })
Show-Page 'PageHome'
[void]$window.ShowDialog()
