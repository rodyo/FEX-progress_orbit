% PROGRESS_ORBIT   progress orbit/trajectory through Kepler state 
%                  transition matrix 
%
% USAGE: 
%   new_state = progress_orbit(time_step, [x y z xdot ydot zdot], GM_central)
%   [x y z xdot ydot zdot] = ...
%              progress_orbit(time_step, x, y, z, xdot, ydot, zdot, GM_central, 'days' or 'seconds')
%
% INPUT:
% ======================
%     x,y,z,     - Initial Cartesian statevector; 3 position coordinates, and     
% xdot,ydot,zdot   3 velocity components. 
%
%      time_step - the time step(s) to take. May be scalar or vector. In
%                  case of a vector, the output arument(s) will have a
%                  number of rows equal to the number of elements in
%                  [time_step].
%
%     GM_central - std. grav. parameter of the central body [km2/s2]
%
%          units - either 'days' (default) or 'seconds'; the units in
%                  which the time step is expressed.
%
% The Kepler State transition matrix provides a way to progress any given
% state vector for a given time step, without having to perform a lengthy
% triple-coordinate conversion (from Cartesian coordinates to Kepler
% elements, progressing, and back). This procedure has been generalized and
% greatly optimized for computational efficiency by Shepperd (1985)[1], who
% used continued fractions to calculate the corresponding solution to
% Kepler's equation. The resulting algorithm is an order of magnitude
% faster that mentioned triple coordinate conversion, which makes it very
% well suited as a basis for a number of other algorithms that require
% frequent progressing of state vectors. 
%
% This procedure implements a robust version of this algorithm. A small
% correction to the original version was made: instead of Newton's method
% to update the Kepler-loop, a Halley-step is used. This change makes the
% algorithm much more robust while increasing the rate of convergence even
% further. If the algorithm fails however, the slower triple-coordinate 
% conversion is automatically started. 
%
%
% References: 
% [1] S.W. Shepperd, "Universal Keplerian State Transition Matrix".
% Celestial Mechanics 35(1985) pp. 129--144, DOI: 0008-8714/85.15
%
% See also kep2cart, cart2kep.
function varargout = progress_orbitM(dts, varargin)
% Please report bugs and inquiries to: 
%
% Name       : Rody P.S. Oldenhuis
% E-mail     : oldenhuis@gmail.com    (personal)
%              oldenhuis@luxspace.lu  (professional)
% Affiliation: LuxSpace s�rl
% Licence    : GPL + anything implied by placing it on the FEX


% If you find this work useful, please consider a donation:
% https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=6G3S5UYM7HJ3N

    
    % standard error
    error(nargchk(3, 9, nargin));%#ok
            
    % parse input
    narg = nargin;
    time_unit = 'days';
    if (narg >= 8)       
        % otherwise
        r1 = [varargin{1:3}];
        v1 = [varargin{4:6}];   
        muC = varargin{7};  
    end
    if (narg == 9), time_unit = varargin{8}; end
    if (narg <= 4)    
        % otherwise
        r1 = varargin{1}(1:3);
        v1 = varargin{1}(4:6);
        muC = varargin{2};        
    end
    if (narg == 4), time_unit = varargin{3}; end    
    
    % force everyting to be row-matrices
    r1 = r1(:).';   v1 = v1(:).';
    
    % initialize output
    zero                        = zeros(numel(dts), 1);
    exitflag                    = zero;
    final_states                = NaN(numel(dts), 6);
    output.Kepler_iterations    = zero;
    output.cont_frac_iterations = zero;
    output.time_error           = zero;
    
    % progress only one orbit (to command window, debugging puruposes only)
    if numel(r1) ~= 3
        error('progress_orbit:only_one_body_allowed',...
              'I can only progress one orbit at a time. Please use ARRAYFUN().');
    end
      
    % times are given in days, unless specified otherwise
    if strcmpi(time_unit, 'days')
        dts = dts * 86400;   
    elseif ~strcmpi(time_unit, 'seconds')
        error('progress_orbit:invalid_timeunit',...
            'Only ''seconds'' and ''days'' are valid timeunits.');
    end
    
    % intitialize
    nu0  = r1*v1.';
    r1m  = sqrt(r1*r1.');
    beta = 2*muC/r1m - v1*v1.';
    
    % period effects
    DeltaU = zero;
    if (beta > 0)
        P = 2*pi*muC*beta^(-3/2);
        n = floor((dts + P/2 - 2*nu0/beta)/P);
        DeltaU = 2*pi*n*beta^(-5/2);
    end
    
    % loop through all requested time steps
    for i = 1:numel(dts)
        
        % extract current time step
        dt = dts(i);
        
        % quick exit for trivial case
        if (dt == 0)
            final_states(i, :) = [r1,v1];
            exitflag(i) = 1;
            output.Kepler_iterations(i)    = 0;
            output.cont_frac_iterations(i) = 0;
            output.time_error(i)           = 0;
            continue;
        end 
        
        % loop until convergence of the time step
        u = 0; t = 0; qisbad = false; iter = 0; cont_frac = 0; deltaT = t-dt;
        while abs(deltaT) > 1 % one second accuracy seems fine
            
            % increase iterations
            iter = iter + 1;
            
            % compute q
            % NOTE: [q] may not exceed 1/2. In principle, this will never 
            % occur, but the iterative nature of the procedure can bring 
            % it above 1/2 for some iterations.
            bu = beta*u*u;
            q  = bu/(1 + bu);
            
            % escape clause;
            % The value for [q] will almost always stabilize to a value less 
            % than 1/2 after a few iterations, but NOT always. In those
            % cases, just use repeated coordinate transformations
            if (iter > 25) || (q >= 1), qisbad = true; break; end
            
            % evaluate continued fraction (when q < 1, always converges)
            A =  1;   B = 1;   G = 1;   n = 0;
            k = -9;   d = 15;  l = 3;   Gprev = inf;
            while abs(G-Gprev) > 1e-14
                k = -k;                 l = l + 2;
                d = d + 4*l;            n = n + (1+k)*l;
                A = d/(d - n*A*q);      B = (A-1)*B;
                Gprev = G;              G = G + B;
                cont_frac = cont_frac + 1;
            end % continued fraction evaluation
            
            % continue kepler loop
            U0w2   = 1 - 2*q;
            U1w2   = 2*(1-q)*u;
            U      = 16/15*U1w2^5*G + DeltaU(i);
            U0     = 2*U0w2^2-1;
            U1     = 2*U0w2*U1w2;
            U2     = 2*U1w2^2;
            U3     = beta*U + U1*U2/3;
            r      = r1m*U0 + nu0*U1 + muC*U2;
            t      = r1m*U1 + nu0*U2 + muC*U3;
            deltaT = t - dt;
            % Newton-Raphson method works most of the time, but is 
            % not too stable; the method fails far too often for my
            % liking...
            % u = u - deltaT/4/(1-q)/r; 
            % Halley's method is much better in that respect. Working 
            % out all substitutions and collecting terms gives the 
            % following simplification:
            u = u - deltaT/((1-q)*(4*r + deltaT*beta*u));

        end % time loop
                
        % do it the slow way if state transition matrix fails for some q
        if qisbad
            % repeated coordinate transformations
            [aa, ee, ii, OO, oo, M] = cart2kep([r1, v1], muC, 'M');
            M = M + sqrt(muC/abs(aa)^3)*dt;
            [x, y, z, xd, yd, zd] = kep2cart(aa, ee, ii, OO, oo, M, muC, 'M');
            final_states(i, :) = [x, y, z, xd, yd, zd];
            % this means failure
            exitflag(i) = -1;            
            
        % use state transition matrix if all went well
        else
            % Kepler solution
            f = 1 - muC/r1m*U2;     F = -muC*U1/r/r1m;
            g = r1m*U1 + nu0*U2;    G = 1 - muC/r*U2;
            % create new position and velocity matrices
            final_states(i, :) = [r1*f+v1*g, r1*F+v1*G]; 
            % all went fine
            exitflag(i) = 1;
        end % "q is bad" clause
        
        % process output
        output.Kepler_iterations(i)    = iter;
        output.cont_frac_iterations(i) = cont_frac;
        output.time_error(i)           = abs(t-dt);
        
    end % loop through [dt]
    
    % generate properly formatted output
    narg = nargout;
    if (narg <= 3)
        varargout{1} = final_states;     % and output array
        varargout{2} = exitflag;         % exitflag
        varargout{3} = output;           % output
    elseif (narg > 3)
        varargout{1} = final_states(:, 1);  varargout{4} = final_states(:, 4);
        varargout{2} = final_states(:, 2);  varargout{5} = final_states(:, 5);
        varargout{3} = final_states(:, 3);  varargout{6} = final_states(:, 6);
        varargout{7} = exitflag;         % exitflag
        varargout{8} = output;           % output
    end % process output
    
end % progress orbit
