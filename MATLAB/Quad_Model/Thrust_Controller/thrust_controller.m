function [ ] = thrust_controller( q_d )
%THRUST_CONTROLLER Implements the thrust direction controller
    
    global t t_s q torque_xy torque_z c_phi phi_low phi_up torques phi brake_torque v_1 v_2 d d_z r delta_phi w s_surf phi_dotv J_x;
    
    
    i = round(t/t_s);
    
    if i > 1
    
        
        % extract the attitude error for the xy plane
        
        q_error = quat_mult(quat_conjugate(q(i-1,:)),q_d);

        q_hat = q_error.*sign_l(q_error(4));
        
        q_z = get_z_from_quat(q_hat);
        q_xy = quat_mult_inv(q_z,q_hat);
        
        
        q_x = q_xy(1);
        q_y = q_xy(2);
        qp = q_xy(4);
        
        % get the error between the desired thrust direction and the
        % current one
        
        phi(i) = 2*acos(qp);
        
        if i == 2
            phi(1)=phi(2);
        end
        
        torque_phi = 0;
        
        
        % Compute the torque field generated by the desired potential
        % energy: thrust vector will behave like a torsion spring with
        % saturation around the equilibrium
        
        if phi(i) >= 0 && phi(i) <= phi_low
            
            torque_phi = c_phi * phi(i); % small error -> torsion spring behavior
            
        else if phi(i) > phi_low && phi(i) <= phi_up
                
                torque_phi = c_phi*phi_low; % saturation -> big error
                
            else if phi(i) > phi_up && phi(i) <= pi
                    
                    torque_phi = c_phi*(pi-phi(i))/(pi-phi_up); % vanish to zero to avoid singularity
                    
                end
                
            end
            
        end
        
        if qp ~=1
            torque_field = torque_phi * (1/(sqrt(1-qp^2)))*[q_x, q_y 0];
        else
            torque_field = [0 0 0]; %% qp==1 -> zero error
        end
        
        
        % Compute the damping matrix
        
        % Beta is the term that ensures that the damping matrix won't go to
        % infinity when qp ->1
        
        if phi(i) >= 0 && phi(i) <= phi_up
            
            Beta = 1;
            
        else if phi(i) > phi_up && phi(i) <= pi
                
                Beta = (pi-phi(i))/(pi-phi_up);
            
            end
            
        end
        
        % Compute the damping of the thrust axis: for a large error, it
        % should favor accelerations that go in ways to minimize it and
        % damp them otherwise. For a small error it should always damp the
        % movement, to allow for a smooth settling
        
        phi_dot = (phi(i)-phi(i-1))/t_s;
        
        % The switching curve defines wether we should accelerate or
        % deaccelerate the axis movement
        
        
        if v_2^2-2*(brake_torque*(phi_low-phi(i)))/J_x > 0
            switch_curve = -sqrt(v_2^2-2*(brake_torque*(phi_low-phi(i)))/J_x);
        else
            switch_curve = 0;
        end
        s_surf(i) = switch_curve;
         phi_dotv(i) = phi_dot;
        
        if i == 2
            phi_dotv(1) = phi_dot;
            s_surf(1) = s_surf(2);
        end
        
       
        
        if phi_dot > v_1
            
            d_acc = -c_phi*phi_low/phi_dot + brake_torque/phi_dot;
            
        else if phi_dot > 0 && phi_dot <= v_1
                
                d_acc = -c_phi * phi_low /v_1 + brake_torque/v_1;
                
            else
                
                d_acc = 0;
                
            end
            
        end
        
        d_dec = -c_phi*phi_low/phi_dot-brake_torque/phi_dot;
        
        d_mix = d_acc + (phi_dot-r*switch_curve)/((1-r)*switch_curve)*(d_dec-d_acc);
        
        if phi_dot > r*switch_curve
            
            d_xy_up = d_acc;
            
        else if phi_dot > switch_curve && phi_dot <= r*switch_curve
                
                d_xy_up = d_mix;
                
            else if phi_dot >= switch_curve
                    
                    d_xy_up = d_dec;
                    
                else
                    d_xy_up = 0;
                    
                end
                
            end
            
        end
        
        % :(
        if i == 2
            d_xy_up = 0;
        end
        
        d_xy_low = d;
        
        d_xy_mix = d_xy_low + (phi(i)-phi_low)/delta_phi*(d_xy_up-d_xy_low);
        
        if phi(i) < phi_low
            
            d_xy = d_xy_low;
            
        else if phi(i) >= phi_low && phi(i) <= phi_low + delta_phi
                
                d_xy = d_xy_mix;
                
            else if phi(i) >= phi_low + delta_phi
                    
                    d_xy = d_xy_up;
                    
                end
                
            end
            
        end

        if qp ~=1
            D_xy = Beta/(1-qp^2)*(d_xy*[q_x^2, q_x*q_y; q_x*q_y q_y^2] + d*[q_y^2 -q_x*q_y; -q_x*q_y q_x^2]);
        else
            D_xy = [0 0; 0 0];
        
        end
        
        % Compute the damping gains. Assuming c_phi was properly chosen, they will ensure that the control torques will be saturated 
        
        T_xy = zeros(2,1);
        w_xy = zeros(2,1);
        T_xy = torque_field(1:2)';
        w_xy = w(i-1,1:2)';
        
        a=D_xy(1,1)*w_xy(1)+D_xy(1,2)*w_xy(2);
        b=D_xy(2,1)*w_xy(1)+D_xy(2,2)*w_xy(2);
        
        sq = (T_xy(1)^2+T_xy(2)^2-torque_xy^2)*(a^2+b^2);
        
        if  sq < 0 || (a^2+b^2) == 0
            
            k_1 = 1;
            
        else if sqrt(sq) > 2*(T_xy(1)*a+T_xy(2)*b)
                
                k_1 = (2*(T_xy(1)*a+T_xy(2)*b)+sqrt(4*sq))/(2*(a^2+b^2));
                
            else
                
                k_1 = (2*(T_xy(1)*a+T_xy(2)*b)-sqrt(4*sq))/(2*(a^2+b^2));
                
            end
            
        end
        
        if k_1 > 1
            
            k_1 = 1;
            
        else if k_1 < 0
                
                k_1 = 0;
                
            end
            
        end
        
        k_2 = torque_z/abs(d_z*w(i-1,3));
        
        if k_2 > 1
            
            k_2 = 1;
            
        end
        

        D=[k_1*D_xy, zeros(2,1); zeros(1,2) d_z*k_2];
           
        
        torques(i,:) = torque_field-(D*w(i-1,:)')';
        
    end
    


end
