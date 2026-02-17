% plot_experimentA_localization_XKF1_3D.m
% Experiment A plots using high-rate EKF output (XKF1) vs OptiTrack VISP
% Updated for full 3D localization reporting.
%
% Outputs (./figs, vector PDF):
%   Fig01_Headline_XY_Overlay.pdf
%   Fig02_Position_vs_Time_3D.pdf          (N, E, Height in one figure)
%   Fig03_Error_vs_Time_3D_withStats.pdf   (eN, eE, eH, ||e_xy||, ||e_3D|| + stats box)
%   Fig04_Error_CDF_2D_3D.pdf              (CDF of ||e_xy|| and ||e_3D||)
%
% Notes:
%   - EKF: XKF1_0 (PN/PE/PD, optionally VN/VE)
%   - OptiTrack: VISP (PX/PY/PZ)
%   - Time-bias estimated via velocity correlation sweep (optional)
%   - Tare (origin) computed from mean over initial hover window (default 3 s)
%
% Frederick Kwaku Richter — 2026-01-27

clear; clc;

%% ---------------- User settings ----------------
matFile = "log_13_UnknownDate.mat";

outDir  = "figs";
savePDF = true;     % vector PDF
savePNG = false;    % optional raster preview
dpiPNG  = 300;

tareSec = 3.0;      % initial hover duration for origin tare

autoTimeBias = true;
manualTimeBiasSec = 0.0;
biasSearchRange = 0.50;   % seconds
biasStep        = 0.005;  % seconds

xyLim = [];
tLim  = [];

%% ---------------- Discover variable names robustly ----------------
vars = whos("-file", matFile);
names = string({vars.name});

xkfCandidates = names(startsWith(names, "XKF1") & ~endsWith(names, "_label"));
assert(~isempty(xkfCandidates), "Could not find XKF1 data matrix in MAT file.");
xkfName = xkfCandidates(1);

assert(any(names == "VISP"), "Could not find VISP in MAT file.");
assert(any(names == "XKF1_label"), "Missing XKF1_label in MAT file.");
assert(any(names == "VISP_label"), "Missing VISP_label in MAT file.");

fprintf("Using EKF source: %s\n", xkfName);

%% ---------------- Load required vars ----------------
S = load(matFile, xkfName, "XKF1_label", "VISP", "VISP_label");
XKF = S.(xkfName);
XKF_label = S.XKF1_label;

VISP = S.VISP;
VISP_label = S.VISP_label;

%% ---------------- Helpers ----------------
getcol = @(M, labels, name) M(:, find(strcmp(string(labels), name), 1, "first"));
mustHave = @(labels, name) assert(any(strcmp(string(labels), name)), ...
    "Missing column '%s' in labels.", name);

mustHave(XKF_label, "TimeUS");
mustHave(XKF_label, "PN"); mustHave(XKF_label, "PE"); mustHave(XKF_label, "PD");
hasVN = any(strcmp(string(XKF_label), "VN"));
hasVE = any(strcmp(string(XKF_label), "VE"));

mustHave(VISP_label, "TimeUS");
mustHave(VISP_label, "PX"); mustHave(VISP_label, "PY"); mustHave(VISP_label, "PZ");

%% ---------------- Extract data ----------------
tE_all = getcol(XKF, XKF_label, "TimeUS") * 1e-6;
pn_all = getcol(XKF, XKF_label, "PN");
pe_all = getcol(XKF, XKF_label, "PE");
pd_all = getcol(XKF, XKF_label, "PD");  % Down-positive

if hasVN && hasVE
    vEn_all = getcol(XKF, XKF_label, "VN");
    vEe_all = getcol(XKF, XKF_label, "VE");
else
    vEn_all = gradient(pn_all, tE_all);
    vEe_all = gradient(pe_all, tE_all);
end

tV_all = getcol(VISP, VISP_label, "TimeUS") * 1e-6;
px_all = getcol(VISP, VISP_label, "PX");
py_all = getcol(VISP, VISP_label, "PY");
pz_all = getcol(VISP, VISP_label, "PZ");

%% ---------------- Trim to overlap ----------------
t0 = max(min(tE_all), min(tV_all));
t1 = min(max(tE_all), max(tV_all));

maskE = (tE_all >= t0) & (tE_all <= t1);
maskV = (tV_all >= t0) & (tV_all <= t1);

tE = tE_all(maskE); pn = pn_all(maskE); pe = pe_all(maskE); pd = pd_all(maskE);
vEn = vEn_all(maskE); vEe = vEe_all(maskE);

tV = tV_all(maskV); px = px_all(maskV); py = py_all(maskV); pz = pz_all(maskV);

%% ---------------- Estimate time bias ----------------
if autoTimeBias
    fprintf("Estimating time bias via velocity correlation sweep (±%.3fs, step %.3fs)...\n", biasSearchRange, biasStep);

    biases = -biasSearchRange:biasStep:biasSearchRange;
    scores = nan(size(biases));

    for k = 1:numel(biases)
        b = biases(k);

        px_i = interp1(tV - b, px, tE, "linear", NaN);
        py_i = interp1(tV - b, py, tE, "linear", NaN);

        good = ~(isnan(px_i) | isnan(py_i));
        if nnz(good) < 50
            continue;
        end

        vVn = gradient(px_i(good), tE(good));
        vVe = gradient(py_i(good), tE(good));

        c1 = corr(vEn(good), vVn, "Rows","complete");
        c2 = corr(vEe(good), vVe, "Rows","complete");
        if isnan(c1); c1 = 0; end
        if isnan(c2); c2 = 0; end
        scores(k) = c1 + c2;
    end

    [bestScore, idxBest] = max(scores);
    timeBiasSec = biases(idxBest);
    fprintf("Best time bias: %.4f s (score=%.3f)\n", timeBiasSec, bestScore);
else
    timeBiasSec = manualTimeBiasSec;
    fprintf("Using manual time bias: %.4f s\n", timeBiasSec);
end

%% ---------------- Resample VISP onto EKF time ----------------
px_i = interp1(tV - timeBiasSec, px, tE, "linear", NaN);
py_i = interp1(tV - timeBiasSec, py, tE, "linear", NaN);
pz_i = interp1(tV - timeBiasSec, pz, tE, "linear", NaN);

good = ~(isnan(px_i) | isnan(py_i) | isnan(pz_i));
tE = tE(good); pn = pn(good); pe = pe(good); pd = pd(good);
px_i = px_i(good); py_i = py_i(good); pz_i = pz_i(good);

t = tE - tE(1);

%% ---------------- Convert to height (Up-positive) ----------------
hE = -pd;     % EKF height (Up)
hV = -pz_i;   % OptiTrack height (Up) assuming PZ is Up-positive; if not, flip sign here

%% ---------------- Tare using initial hover window ----------------
idx0 = t <= tareSec;
if nnz(idx0) < 20
    warning("Tare window too short after trimming. Falling back to first sample.");
    idx0 = false(size(t)); idx0(1) = true;
end

%pn_ref = mean(pn(idx0)); pe_ref = mean(pe(idx0)); hE_ref = mean(hE(idx0));
%px_ref = mean(px_i(idx0)); py_ref = mean(py_i(idx0)); hV_ref = mean(hV(idx0));

pn_ref = mean(pn(idx0)); pe_ref = mean(pe(idx0)); hE_ref = 0;
px_ref = mean(px_i(idx0)); py_ref = mean(py_i(idx0)); hV_ref = 0;

pn0 = pn - pn_ref;  pe0 = pe - pe_ref;  hE0 = hE - hE_ref;
px0 = px_i - px_ref; py0 = py_i - py_ref; hV0 = hV - hV_ref;

%% ---------------- Errors and metrics (3D) ----------------
eN = pn0 - px0;
eE = pe0 - py0;
eH = hE0 - hV0;

e2 = hypot(eN, eE);
e3 = sqrt(eN.^2 + eE.^2 + eH.^2);

rmseN = sqrt(mean(eN.^2));
rmseE = sqrt(mean(eE.^2));
rmseH = sqrt(mean(eH.^2));
rmse2 = sqrt(mean(e2.^2));
rmse3 = sqrt(mean(e3.^2));

med2 = median(e2);  p95_2 = prctile(e2,95);  max2 = max(e2);
med3 = median(e3);  p95_3 = prctile(e3,95);  max3 = max(e3);

fprintf("\nExperiment A (3D) using %s, after time-bias + %.1fs tare:\n", xkfName, tareSec);
fprintf("  Time bias = %.3f s\n", timeBiasSec);
fprintf("  RMSE_N=%.3f m, RMSE_E=%.3f m, RMSE_H=%.3f m\n", rmseN, rmseE, rmseH);
fprintf("  RMSE_2D=%.3f m, RMSE_3D=%.3f m\n", rmse2, rmse3);
fprintf("  2D: median=%.3f, 95%%=%.3f, max=%.3f\n", med2, p95_2, max2);
fprintf("  3D: median=%.3f, 95%%=%.3f, max=%.3f\n", med3, p95_3, max3);

%% ---------------- Paper formatting (single-column) ----------------
if ~exist(outDir, "dir"); mkdir(outDir); end

% Target single-column figure size (adjust if your template differs)
paper.colWidthIn   = 3.39;           % inches (IEEE single column ~3.39")
paper.fontName     = "Times New Roman";
paper.fontSize     = 7;              % pt
paper.monoFontName = "Consolas";     % for stats boxes
paper.lineWidth    = 1.0;
paper.markerSize   = 5;
paper.gridAlpha    = 0.15;

% Per-figure heights (inches) tuned for this script
paper.hFig01 = 2.0;   % XY overlay
paper.hFig02 = 2.9;   % 3 stacked position plots
paper.hFig03 = 4.2;   % 5 stacked error plots
paper.hFig04 = 2.0;   % CDF

applyPaperDefaults(paper);

% Stats strings (used in Fig03 text boxes)
stats2D = sprintf([ ...
    'RMSE:   %.2f m' ...
    'Median: %.2f m' ...
    '95%%%%:    %.2f m' ...
    'Max:    %.2f m' ], rmse2, med2, p95_2, max2);

stats3D = sprintf([ ...
    'RMSE:   %.2f m' ...
    'Median: %.2f m' ...
    '95%%%%:    %.2f m' ...
    'Max:    %.2f m' ], rmse3, med3, p95_3, max3);

%% ---------------- Fig 01: Headline XY overlay ----------------
fig = makePaperFigure(1, paper, paper.hFig01); clf(fig); hold on; grid on; axis equal;
%plot(px0, py0, "-", "DisplayName", "OptiTrack ground truth");
%plot(pn0, pe0, "--", "DisplayName", "Onboard EKF");
plot(px0, py0, "-", "DisplayName", "O. T.");
plot(pn0, pe0, "--", "DisplayName", "EKF");
scatter(px0(1), py0(1), 36, "filled", "DisplayName", "Start");
xlabel("North [m]");
ylabel("East [m]");
%title(sprintf("Experiment A: XY Overlay (RMSE_{2D}=%.2f m)", rmse2));
title(sprintf("Experiment A: XY Ground Track"));
legend("Location","northwest");
if ~isempty(xyLim); axis(xyLim); end
saveFig(fig, outDir, "Fig01_Headline_XY_Overlay", savePDF, savePNG, dpiPNG);

%% ---------------- Fig 02: Position vs Time (N, E, Height) ----------------
fig = makePaperFigure(2, paper, paper.hFig02); clf(fig);

tl = tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

nexttile; hold on; grid on;
plot(t, px0, "-",  "DisplayName","OptiTrack N");
plot(t, pn0, "--", "DisplayName","EKF N");
ylabel("North [m]");
%title(sprintf("Position vs Time (tare=%.1fs, bias=%.3fs)", tareSec, timeBiasSec));
title(sprintf("EKF Position Estimate vs OptiTrack Benchmark"));
%legend("Location","best");

nexttile; hold on; grid on;
plot(t, py0, "-",  "DisplayName","OptiTrack E");
plot(t, pe0, "--", "DisplayName","EKF E");
ylabel("East [m]");
%legend("Location","best");

nexttile; hold on; grid on;
%plot(t, hV0, "-",  "DisplayName","OptiTrack H");
%plot(t, hE0, "--", "DisplayName","EKF H");
plot(t, hV0, "-",  "DisplayName","OptiTrack");
plot(t, hE0, "--", "DisplayName","EKF");
ylabel("Height [m]");
xlabel("Time [s]");
legend("Location","best");

if ~isempty(tLim)
    ax = findall(fig,'Type','axes');
    for k = 1:numel(ax)
        xlim(ax(k), tLim);
    end
end

saveFig(fig, outDir, "Fig02_Position_vs_Time_3D", savePDF, savePNG, dpiPNG);

%% ---------------- Fig 03: Error vs Time (with stats) ----------------
fig = makePaperFigure(3, paper, paper.hFig03); clf(fig);

%tl = tiledlayout(5,1,'TileSpacing','compact','Padding','compact');
tl = tiledlayout(4,1,'TileSpacing','compact','Padding','compact');

nexttile; hold on; grid on;
plot(t, eN);
ylabel("e_N [m]");
%title(sprintf("Localization Error, time bias = %.3fs", timeBiasSec));
title(sprintf("Localization Error"));

nexttile; hold on; grid on;
plot(t, eE);
ylabel("e_E [m]");

nexttile; hold on; grid on;
plot(t, eH);
ylabel("e_H [m]");

%nexttile; hold on; grid on;
%plot(t, e2);
%ylabel("||e_{xy}|| [m]");
%text(0.80, 0.95, stats2D, ...
%    'Units','normalized', ...
%    'HorizontalAlignment','left', ...
%    'VerticalAlignment','top', ...
%    'BackgroundColor','w', ...
%    'EdgeColor',[0.3 0.3 0.3], ...
%    'Margin',4, ...
%    'FontName',paper.monoFontName, ...
%    'FontSize',paper.fontSize-1, ...
%    'Interpreter','none');

nexttile; hold on; grid on;
plot(t, e3);
ylabel("||e_{3D}|| [m]");
xlabel("Time [s]");
%text(0.80, 0.95, stats3D, ...
%    'Units','normalized', ...
%    'HorizontalAlignment','left', ...
%    'VerticalAlignment','top', ...
%    'BackgroundColor','w', ...
%    'EdgeColor',[0.3 0.3 0.3], ...
%    'Margin',4, ...
%    'FontName',paper.monoFontName, ...
%    'FontSize',paper.fontSize-1, ...
%    'Interpreter','none');

if ~isempty(tLim)
    ax = findall(fig,'Type','axes');
    for k = 1:numel(ax)
        xlim(ax(k), tLim);
    end
end

saveFig(fig, outDir, "Fig03_Error_vs_Time_3D_withStats", savePDF, savePNG, dpiPNG);

%% ---------------- Fig 04: CDF for 2D and 3D errors ----------------
fig = makePaperFigure(4, paper, paper.hFig04); clf(fig); hold on; grid on;

%[e2s, ~] = sort(e2);
%p2 = (1:numel(e2s)) / numel(e2s);
%plot(e2s, p2, "DisplayName","||e_{xy}||");

[e3s, ~] = sort(e3);
p3 = (1:numel(e3s)) / numel(e3s);
plot(e3s, p3, "DisplayName","||e_{3D}||");

xlabel("Error magnitude [m]");
ylabel("Empirical CDF");
title("Error Distribution (||e_{3D}||)");
%legend("Location","best");

saveFig(fig, outDir, "Fig04_Error_CDF_2D_3D", savePDF, savePNG, dpiPNG);

disp("Done. Figures saved to: " + outDir);

%% ---------------- Local functions ----------------
function applyPaperDefaults(paper)
    % Global defaults for consistent paper-style figures
    set(0, "defaultFigureColor", "w");
    set(0, "defaultAxesFontName", paper.fontName);
    set(0, "defaultTextFontName", paper.fontName);
    set(0, "defaultAxesFontSize", paper.fontSize);
    set(0, "defaultTextFontSize", paper.fontSize);
    set(0, "defaultLineLineWidth", paper.lineWidth);
    set(0, "defaultAxesLineWidth", 0.8);
    set(0, "defaultAxesBox", "on");

    % Some defaults are version-dependent; guard them.
    try
        set(0, "defaultLineMarkerSize", paper.markerSize);
    catch
    end
    try
        set(0, "defaultAxesGridAlpha", paper.gridAlpha);
    catch
    end
end

function fig = makePaperFigure(figNum, paper, heightIn)
    % Create/resize a figure to single-column size for high-quality export
    fig = figure(figNum);
    set(fig, "Color", "w", "Units", "inches");
    set(fig, "Position", [1 1 paper.colWidthIn heightIn]);
    set(fig, "Renderer", "painters");         % best for vector PDF
    set(fig, "InvertHardcopy", "off");        % keep white background
    set(fig, "PaperPositionMode", "auto");    % match on-screen size
end

function saveFig(figHandle, outDir, baseName, savePDF, savePNG, dpiPNG)
    if savePDF
        exportgraphics(figHandle, fullfile(outDir, baseName + ".pdf"), ...
            "ContentType","vector");
    end
    if savePNG
        exportgraphics(figHandle, fullfile(outDir, baseName + ".png"), ...
            "Resolution", dpiPNG);
    end
end