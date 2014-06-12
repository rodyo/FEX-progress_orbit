% Please report bugs and inquiries to: 
%
% Name       : Rody P.S. Oldenhuis
% E-mail     : oldenhuis@gmail.com    (personal)
%              oldenhuis@luxspace.lu  (professional)
% Affiliation: LuxSpace sàrl
% Licence    : GPL + anything implied by placing it on the FEX


% If you find this work useful, please consider a donation:
% https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=6G3S5UYM7HJ3N


% 36526 times
clc
dt = 0:10:1000*365.25;
Mtime = zeros(numel(dt), 1);
MEXtime = Mtime;

state = [150e6, 0, -2e3, 1.2, 29.4, 0.01];
muC   = 1.32e11;


for ii = 1:numel(dt)
    
    % get 100 random days
    TIMES = dt(round( 36525*rand(100,1)+1 ));
    
    % show progress
    fprintf(1, '%3d%% complete...', round(100*ii/numel(dt)));
    
    % test M-version
    start = tic;
        A = progress_orbitM(TIMES, state, muC); %#ok<SNASGU>
    Mtime(ii) = toc(start);
    
    % test MEX-version
    start = tic;
        B = progress_orbit(TIMES(:), state, muC); %#ok<SNASGU>
    MEXtime(ii) = toc(start);
    
    % delete progress
    fprintf(1, '\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b');
end

% plot speedup
figure(1), hold on
plot(1:numel(dt), Mtime./MEXtime, 'b')

