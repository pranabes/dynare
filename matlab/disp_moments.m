function oo_=disp_moments(y,var_list,M_,options_,oo_)
% function disp_moments(y,var_list,M_,options_,oo_)
% Displays moments of simulated variables
% INPUTS
%   y                   [double]       nvar*nperiods vector of simulated variables.
%   var_list            [char]         nvar character array with names of variables.
%   M_                  [structure]    Dynare's model structure
%   oo_                 [structure]    Dynare's results structure
%   options_            [structure]    Dynare's options structure
%    
% OUTPUTS
%   oo_                 [structure]    Dynare's results structure,

% Copyright (C) 2001-2015 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

warning_old_state = warning;
warning off

if size(var_list,1) == 0
    var_list = M_.endo_names(1:M_.orig_endo_nbr, :);
end

nvar = size(var_list,1);
ivar=zeros(nvar,1);
for i=1:nvar
    i_tmp = strmatch(var_list(i,:),M_.endo_names,'exact');
    if isempty(i_tmp)
        error (['One of the variable specified does not exist']) ;
    else
        ivar(i) = i_tmp;
    end
end

y = y(ivar,options_.drop+1:end)';

m = mean(y);

% filter series
y=get_filtered_time_series(y,m,options_);

s2 = mean(y.*y);
s = sqrt(s2);
oo_.mean = transpose(m);
oo_.var = y'*y/size(y,1);

labels = deblank(M_.endo_names(ivar,:));

if options_.nomoments == 0
    z = [ m' s' s2' (mean(y.^3)./s2.^1.5)' (mean(y.^4)./(s2.*s2)-3)' ];    
    title='MOMENTS OF SIMULATED VARIABLES';
    if options_.hp_filter
        title = [title ' (HP filter, lambda = ' ...
                 num2str(options_.hp_filter) ')'];
    end
    headers=char('VARIABLE','MEAN','STD. DEV.','VARIANCE','SKEWNESS', ...
                 'KURTOSIS');
    dyntable(title,headers,labels,z,size(labels,2)+2,16,6);
end

if options_.nocorr == 0
    corr = (y'*y/size(y,1))./(s'*s);
    if options_.contemporaneous_correlation 
        oo_.contemporaneous_correlation = corr;
    end
    if options_.noprint == 0
        title = 'CORRELATION OF SIMULATED VARIABLES';
        if options_.hp_filter
            title = [title ' (HP filter, lambda = ' ...
                     num2str(options_.hp_filter) ')'];
        end
        headers = char('VARIABLE',M_.endo_names(ivar,:));
        dyntable(title,headers,labels,corr,size(labels,2)+2,8,4);
    end
end

if options_.noprint == 0 && length(options_.conditional_variance_decomposition)
   fprintf('\nSTOCH_SIMUL: conditional_variance_decomposition requires theoretical moments, i.e. periods=0.\n') 
end

ar = options_.ar;
if ar > 0
    autocorr = [];
    for i=1:ar
        oo_.autocorr{i} = y(ar+1:end,:)'*y(ar+1-i:end-i,:)./((size(y,1)-ar)*std(y(ar+1:end,:))'*std(y(ar+1-i:end-i,:)));
        autocorr = [ autocorr diag(oo_.autocorr{i}) ];
    end
    if options_.noprint == 0
        title = 'AUTOCORRELATION OF SIMULATED VARIABLES';
        if options_.hp_filter
            title = [title ' (HP filter, lambda = ' ...
                     num2str(options_.hp_filter) ')'];
        end
        headers = char('VARIABLE',int2str([1:ar]'));
        dyntable(title,headers,labels,autocorr,size(labels,2)+2,8,4);
    end
end


if ~options_.nodecomposition
    if M_.exo_nbr == 1
        oo_.variance_decomposition = 100*ones(nvar,1);
    else
        oo_.variance_decomposition=zeros(nvar,M_.exo_nbr);
        %get starting values
        if isempty(M_.endo_histval)
            y0 = oo_.dr.ys;
        else
            y0 = M_.endo_histval;
        end
        %back out shock matrix used for generating y
        i_exo_var = setdiff([1:M_.exo_nbr],find(diag(M_.Sigma_e) == 0)); % find shocks with 0 variance
        chol_S = chol(M_.Sigma_e(i_exo_var,i_exo_var)); %decompose rest
        shock_mat=zeros(options_.periods,M_.exo_nbr); %initialize
        shock_mat(:,i_exo_var)=oo_.exo_simul(:,i_exo_var)/chol_S; %invert construction of oo_.exo_simul from simult.m
        
        for shock_iter=1:length(i_exo_var)
            temp_shock_mat=zeros(size(shock_mat));
            temp_shock_mat(:,i_exo_var(shock_iter))=shock_mat(:,i_exo_var(shock_iter));
            temp_shock_mat(:,i_exo_var) = temp_shock_mat(:,i_exo_var)*chol_S;
            y_sim_one_shock = simult_(y0,oo_.dr,temp_shock_mat,options_.order);
            y_sim_one_shock=y_sim_one_shock(ivar,1+options_.drop+1:end)';
            y_sim_one_shock=get_filtered_time_series(y_sim_one_shock,mean(y_sim_one_shock),options_);
            oo_.variance_decomposition(:,i_exo_var(shock_iter))=var(y_sim_one_shock)./s2*100;
        end
        if ~options_.noprint %options_.nomoments == 0
            skipline()
            title='VARIANCE DECOMPOSITION SIMULATING ONE SHOCK AT A TIME (in percent)';
            if options_.hp_filter
                title = [title ' (HP filter, lambda = ' ...
                    num2str(options_.hp_filter) ')'];
            end
            headers = M_.exo_names;
            headers(M_.exo_names_orig_ord,:) = headers;
            headers = char(' ',headers);
            lh = size(deblank(M_.endo_names(ivar,:)),2)+2;
            dyntable(title,char(headers,'Total linear contrib.'),deblank(M_.endo_names(ivar,:)),[oo_.variance_decomposition sum(oo_.variance_decomposition,2)],lh,8,2);
            if options_.order == 1
                fprintf('Note: numbers do not add up to 100 due to non-zero correlation of simulated shocks in small samples\n\n')
            else
                fprintf('Note: numbers do not add up to 100 due to i) non-zero correlation of simulated shocks in small samples and ii) nonlinearity\n\n')
            end
        end

    end
end
        
warning(warning_old_state);
end

function y=get_filtered_time_series(y,m,options_)
        
if options_.hp_filter && ~options.one_sided_hp_filter  && ~options_.bandpass.indicator
    [hptrend,y] = sample_hp_filter(y,options_.hp_filter);
elseif ~options_.hp_filter && options_.one_sided_hp_filter && ~options_.bandpass.indicator
    error('disp_moments:: The one-sided HP filter is not yet available')   
elseif ~options_.hp_filter && ~options_.one_sided_hp_filter && options_.bandpass.indicator
    data_temp=dseries(y,'0q1');
    data_temp=baxter_king_filter(data_temp,options_.bandpass.passband(1),options_.bandpass.passband(2),200);
    y=data_temp.data;
elseif ~options_.hp_filter && ~options_.one_sided_hp_filter  && ~options_.bandpass.indicator
    y = bsxfun(@minus, y, m);
else 
    error('disp_moments:: You cannot use more than one filter at the same time')
end
        
end