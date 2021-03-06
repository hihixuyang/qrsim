classdef TaskKeepSpot10<Task
    % Simple task in which a qudrotor has to keep its starting position despite the wind.
    % Single platform task which requires to maintain the quadrotor hovering at the 
    % position it has when the task starts; the solution requires non constant control 
    % since the helicopter is affected by time varying wind disturbances.
    %
    % KeepSpot methods:
    %   init()   - loads and returns all the parameters for the various simulator objects
    %   reward() - returns the instantateous reward for this task
    %
    % 
    % GENERAL NOTES:
    % - if the on flag is zero, the NOISELESS version of the object is loaded instead
    % - the step dt MUST be always specified eve if on=0
    %
    properties (Constant)
        PENALTY = 1000;  
        U_NEUTRAL = [0;0;0.59;0];
        R = diag([2/pi, 2/pi, 0.5, 1]); %very rough scaling factors
    end    
    
    properties (Access=private)
        initialX;
    end     
    
    methods (Sealed,Access=public)
                        
        function obj = TaskKeepSpot10(state)
           obj = obj@Task(state);             
        end
        
        function taskparams=init(obj) %#ok<MANU>
            % loads and returns all the parameters for the various simulator objects
            %
            % Example:
            %   params = obj.init();
            %          params - all the task parameters
            %
            
            taskparams.dt = 0.02; % task timestep i.e. rate at which controls
                               % are supplied and measurements are received
            
            taskparams.seed = 0; %set to zero to have a seed that depends on the system time
            
            %%%%% visualization %%%%%
            % 3D display parameters
            taskparams.display3d.on = 1;
            taskparams.display3d.width = 1000;
            taskparams.display3d.height = 600;            
            
            %%%%% environment %%%%%
            % these need to follow the conventions of axis(), they are in m, Z down
            % note that the lowest Z limit is the refence for the computation of wind shear and turbulence effects
            taskparams.environment.area.limits = [-120 120 -10 10 -40 0];
            taskparams.environment.area.type = 'BoxArea';
            
            % originutmcoords is the location of the RVC (our usual flying site)
            % generally when this is changed gpsspacesegment.orbitfile and 
            % gpsspacesegment.svs need to be changed
            [E N zone h] = llaToUtm([51.71190;-0.21052;0]);
            taskparams.environment.area.originutmcoords.E = E;
            taskparams.environment.area.originutmcoords.N = N;
            taskparams.environment.area.originutmcoords.h = h;
            taskparams.environment.area.originutmcoords.zone = zone;
            taskparams.environment.area.graphics.type = 'AreaGraphics';
            taskparams.environment.area.graphics.backgroundimage = 'ucl-rvc-zoom.tif';
               
            % GPS
            % The space segment of the gps system
            taskparams.environment.gpsspacesegment.on = 1; % if off the gps returns the noiseless position
            taskparams.environment.gpsspacesegment.dt = 0.2;
            % real satellite orbits from NASA JPL
            taskparams.environment.gpsspacesegment.orbitfile = 'ngs15992_16to17.sp3';
            % simulation start in GPS time, this needs to agree with the sp3 file above, 
            % alternatively it can be set to 0 to have a random initialization
            %taskparams.environment.gpsspacesegment.tStart = Orbits.parseTime(2010,8,31,16,0,0); 
            taskparams.environment.gpsspacesegment.tStart = 0;             
            % id number of visible satellites, the one below are from a typical flight day at RVC
            % these need to match the contents of gpsspacesegment.orbitfile
            taskparams.environment.gpsspacesegment.svs = [3,5,6,7,13,16,18,19,20,22,24,29,31];
            % the following model is from [2]
            %taskparams.environment.gpsspacesegment.type = 'GPSSpaceSegmentGM';
            %taskparams.environment.gpsspacesegment.PR_BETA = 2000;     % process time constant
            %taskparams.environment.gpsspacesegment.PR_SIGMA = 0.1746;  % process standard deviation
            % the following model was instead designed to match measurements of real
            % data, it appears more relistic than the above
            taskparams.environment.gpsspacesegment.type = 'GPSSpaceSegmentGM2';            
            taskparams.environment.gpsspacesegment.PR_BETA2 = 4;       % process time constant
            taskparams.environment.gpsspacesegment.PR_BETA1 =  1.005;  % process time constant   
            taskparams.environment.gpsspacesegment.PR_SIGMA = 0.003;   % process standard deviation            
            
            % Wind
            % i.e. a steady omogeneous wind with a direction and magnitude
            % this is common to all helicopters
            taskparams.environment.wind.on = 0;
            taskparams.environment.wind.type = 'WindConstMean';
            taskparams.environment.wind.direction = degsToRads(45); %mean wind direction, rad clockwise from north set to [] to initialise it randomly
            taskparams.environment.wind.W6 = 0.5;  % velocity at 6m from ground in m/s
            
            %%%%% platforms %%%%%
            % Configuration for each of the platforms
            for i=1:10,
                taskparams.platforms(i).configfile = 'pelican_config';
            end
        end 
        
        function reset(obj) 
            % initial state for each of the platforms
            for i=1:10,
                obj.simState.platforms{i}.setX([-100+20*i;0;-10;0;0;0]);
                obj.initialX(i,:) = obj.simState.platforms{i}.getX();
            end
        end

        function updateReward(obj,U)
           % updates reward
           % in this simple example we only have a quadratic control
           % cost
           
           for i=1:size(U,2)
               u = (U(1:4,i)-obj.U_NEUTRAL);
               obj.currentReward = obj.currentReward - ((obj.R*u)'*(obj.R*u))*obj.simState.DT;
           end
        end
        
        function r=reward(obj) 
            % returns the total reward for this task
            %
            % Example:
            %   r = obj.reward();
            %          r - the reward
            %
            
            valid = 1;
            for i=1:length(obj.simState.platforms)
               valid = valid &&  obj.simState.platforms{i}.isValid();
            end
            
            if(valid)
                r = 0;
                for i=1:length(obj.simState.platforms)
                    e = obj.simState.platforms{i}.getX(1:3);
                    e = e-obj.initialX(i,1:3);
                    % control cost so far plus end cost
                    r = r - e' * e; 
                end
                r = obj.currentReward + r;
            else
                % returning a large penalty in case the state is not valid
                % i.e. the helicopter is out of the area, there was a
                % collision or the helicopter has crashed 
                r = - obj.PENALTY;
            end                
        end 
    end
    
end



% [1] J. Rankin, "An error model for sensor simulation GPS and differential GPS," IEEE
%     Position Location and Navigation Symposium, 1994, pp.260-266.
% [2] Carlson, Justin, "Mapping Large, Urban Environments with GPS-Aided SLAM" (2010).
%     Dissertations. Paper 44.
